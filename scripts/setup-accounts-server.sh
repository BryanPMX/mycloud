#!/usr/bin/env bash
# Run on server-hp: bash scripts/setup-accounts-server.sh ADMIN_EMAIL ADMIN_NAME MEMBER_EMAIL MEMBER_NAME
# Enter the requested temporary Mynube password only at the hidden prompt.
set -euo pipefail
set +x
umask 077
[ "$#" = 4 ] || { echo 'Supply administrator email/name and member email/name.' >&2; exit 1; }
[ "$(hostname)" = server-hp ] || { echo 'This procedure is scoped to server-hp.' >&2; exit 1; }
[ "$(docker inspect mycloud-api-1 --format '{{.State.Running}}')" = true ]
MYCLOUD_ACCOUNT_IMAGE=ghcr.io/bryanpmx/mycloud-backup:sha-c39bde465b9a01771b6cab5d06e392cc5a01fde2@sha256:266d78c7a63d2acdea3f5da1d3cbfe9c45560f1dbbc02b3f170349e4066e62f5
docker pull "$MYCLOUD_ACCOUNT_IMAGE"
docker network inspect mycloud_mycloud_internal >/dev/null
MYCLOUD_ACCOUNT_ENV=''
MYCLOUD_API_PAUSED=0
cleanup() {
  unset MYCLOUD_ACCOUNT_PASSWORD
  if [ -n "$MYCLOUD_ACCOUNT_ENV" ]; then rm -f -- "$MYCLOUD_ACCOUNT_ENV"; fi
  if [ "$MYCLOUD_API_PAUSED" = 1 ]; then
    docker start mycloud-api-1 >/dev/null || echo 'API restart failed; run docker start mycloud-api-1 and report the error.' >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
MYCLOUD_ACCOUNT_ENV=$(mktemp "${TMPDIR:-/tmp}/.mycloud-account-env.XXXXXX")
docker inspect mycloud-api-1 --format '{{json .Config.Env}}' |
  python3 -c 'import json,sys
values=dict(item.split("=",1) for item in json.load(sys.stdin) if "=" in item)
for key in ("DATABASE_URL","REDIS_URL"):
    value=values.get(key,"")
    if not value or "\n" in value or "\r" in value:
        sys.exit("Required private configuration is missing or unsupported; no changes made.")
    sys.stdout.write(key+"="+value+"\n")' > "$MYCLOUD_ACCOUNT_ENV"
IFS= read -r -s -p 'Temporary Mynube password (hidden): ' MYCLOUD_ACCOUNT_PASSWORD < /dev/tty
printf '\n' >&2
[ -n "$MYCLOUD_ACCOUNT_PASSWORD" ] || { echo 'Empty password; no changes made.' >&2; exit 1; }
MYCLOUD_ACCOUNT_ROLLBACK="$HOME/mycloud-account-rollback-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 700 "$MYCLOUD_ACCOUNT_ROLLBACK"
MYCLOUD_API_PAUSED=1
docker stop -t 30 mycloud-api-1 >/dev/null
docker exec mycloud-postgres-1 sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-privileges' > "$MYCLOUD_ACCOUNT_ROLLBACK/postgres.dump"
docker exec -i mycloud-postgres-1 pg_restore --list < "$MYCLOUD_ACCOUNT_ROLLBACK/postgres.dump" >/dev/null
(cd "$MYCLOUD_ACCOUNT_ROLLBACK" && sha256sum postgres.dump > postgres.dump.sha256 && sha256sum -c postgres.dump.sha256)
setup_account() {
  printf '%s' "$MYCLOUD_ACCOUNT_PASSWORD" |
    docker run --rm -i --network mycloud_mycloud_internal \
      --env-file "$MYCLOUD_ACCOUNT_ENV" -e ACCOUNT_SETUP_WRITES_PAUSED=yes \
      --memory 256m --cpus 0.5 --read-only --cap-drop ALL \
      --security-opt no-new-privileges:true --entrypoint account-setup \
      "$MYCLOUD_ACCOUNT_IMAGE" "$@"
}
setup_account --email "$1" --name "$2" --role admin --quota-gib 20 --reset-existing-password
setup_account --email "$3" --name "$4" --role member --quota-gib 20 --create --reset-existing-password
docker start mycloud-api-1 >/dev/null
MYCLOUD_API_PAUSED=0
printf '%s' "$MYCLOUD_ACCOUNT_PASSWORD" | python3 -c '
import ipaddress,json,subprocess,sys,time,urllib.error,urllib.request
password=sys.stdin.read()
networks=json.loads(subprocess.check_output(["docker","inspect","mycloud-api-1","--format","{{json .NetworkSettings.Networks}}"],text=True))
address=networks["mycloud_mycloud_internal"]["IPAddress"]
assert ipaddress.ip_address(address).is_private
base="http://"+address+":8080"
client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
for attempt in range(45):
    try:
        with client.open(base+"/health",timeout=2) as response:
            if response.status==200: break
    except Exception: pass
    time.sleep(1)
else: sys.exit("API did not become healthy; report this result. Passwords were not printed.")
for email,role,label in ((sys.argv[1],"admin","Administrator"),(sys.argv[2],"member","Member")):
    request=urllib.request.Request(base+"/api/v1/auth/login",data=json.dumps({"email":email,"password":password}).encode(),headers={"Content-Type":"application/json"},method="POST")
    try:
        with client.open(request,timeout=15) as response: result=json.load(response)
        user=result["user"]
        if user["role"]!=role: sys.exit(label+" role differed; report this result.")
        print(label+" private login verified; role="+role+"; quota_bytes="+str(user["quota_bytes"]))
    except urllib.error.HTTPError as error:
        sys.exit(label+" login returned HTTP "+str(error.code)+"; no credentials printed.")
    except Exception:
        sys.exit(label+" login check could not complete; no credentials printed.")
' "$1" "$3"
unset MYCLOUD_ACCOUNT_PASSWORD
printf 'ACCOUNT_ROLLBACK=%s\n' "$MYCLOUD_ACCOUNT_ROLLBACK"
echo 'Account setup and private login verification completed.'

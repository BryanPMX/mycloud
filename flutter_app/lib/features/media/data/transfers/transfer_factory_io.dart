import 'dart:io';
import 'upload_journal.dart';
import 'native_upload_journal.dart';
import 'part_transfer.dart';
import 'native_part_transfer.dart';

UploadJournal createUploadJournal() =>
    supportsDeviceBackup ? NativeUploadJournal() : MemoryUploadJournal();
PartTransfer? createNativePartTransfer() =>
    supportsDeviceBackup ? NativePartTransfer() : null;
bool get supportsDeviceBackup => Platform.isIOS || Platform.isAndroid;

import 'upload_journal.dart';
import 'part_transfer.dart';

UploadJournal createUploadJournal() => MemoryUploadJournal();
PartTransfer? createNativePartTransfer() => null;
bool get supportsDeviceBackup => false;

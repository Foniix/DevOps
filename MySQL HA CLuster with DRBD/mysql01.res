resource mysql01 {
 protocol C;
 meta-disk internal;
 device /dev/drbd0;
 disk   /dev/sdb1;
 handlers {
  split-brain "/usr/lib/drbd/notify-split-brain.sh root";
 }
 net {
  allow-two-primaries no;
  after-sb-0pri discard-zero-changes;
  after-sb-1pri discard-secondary;
  after-sb-2pri disconnect;
  rr-conflict disconnect;
 }
 disk {
  on-io-error detach;
 }
 syncer {
  verify-alg sha1;
 }
 on mysqlsrv1 {
  address  [ipnode1]:7789;
 }
 on mysqlsrv2 {
  address  [ipnode2]:7789;
 }
}
#include <fcntl.h>
#include <notify.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

static int touch_file(const char *path) {
  int fd = open(path, O_CREAT | O_WRONLY, 0600);
  if (fd < 0) return 1;
  close(fd);
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: trace_notification_waiter <name> <ready-file> <received-file>\n");
    return 64;
  }
  int token = 0;
  if (notify_register_check(argv[1], &token) != NOTIFY_STATUS_OK) return 1;
  if (touch_file(argv[2]) != 0) return 1;
  for (;;) {
    int notified = 0;
    if (notify_check(token, &notified) != NOTIFY_STATUS_OK) return 1;
    if (notified) {
      int status = touch_file(argv[3]);
      notify_cancel(token);
      return status;
    }
    usleep(1000);
  }
}

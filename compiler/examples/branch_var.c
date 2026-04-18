int main() {
  int i = 0;
  while (i < 5) {
    print_int(i);
    i = i + 1;
  }

  if (i == 5) {
    print_str("done\n");
  } else {
    print_str("unexpected\n");
  }

  return 0;
}

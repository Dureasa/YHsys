int main() {
  int i = 0;
  int sum = 0;
  int arr[8];

  while (i < 8) {
    arr[i] = i * 3 + 1;
    i++;
  }

  i = 0;
  while (i < 8) {
    if ((arr[i] & 1) == 1) {
      sum += arr[i];
    } else if ((arr[i] >> 1) >= 2) {
      sum -= arr[i] / 2;
    } else {
      sum = sum ^ arr[i];
    }
    i++;
  }

  print_int(sum);
  print_int(~sum);
  print_int((sum << 1) | 3);
  return 0;
}

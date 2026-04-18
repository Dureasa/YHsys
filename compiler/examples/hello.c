int main() {
  int x = 6;
  int y = 3;
  int arr[4];
  arr[0] = x + y * 2;
  arr[1] = (x - y) * (x + y);
  arr[2] = arr[0] % 5;
  arr[3] = ~arr[2] & 15;
  x += 10;
  y--;
  if ((x > y) && !(arr[2] == 0)) {
    print_int(arr[0]);
    print_int(arr[1]);
    print_int(arr[2]);
    print_int(arr[3]);
  } else {
    print_str("unexpected\n");
  }
  pause(1);
  return 0;
}

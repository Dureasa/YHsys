int add(int a, int b) {
  return a + b;
}

int mul(int a, int b) {
  return a * b;
}

int echo(int x) {
  print_int(x);
  return x;
}

int idx() {
  return 1;
}

int main() {
  int arr[2];
  arr[idx()] = add(1, 2);
  print_int(arr[1]);
  int y = add(echo(2), mul(3, 4));
  print_int(y);
  echo(add(1, 1));
  return y;
}

int unused_after_main() {
  return 99;
}

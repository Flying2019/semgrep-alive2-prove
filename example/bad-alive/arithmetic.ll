; Bad Alive2 sample: (x+1)+2 -> x+4 (wrong constant)

define i32 @src(i32 %x) {
entry:
  %t1 = add i32 %x, 1
  %t2 = add i32 %t1, 2
  ret i32 %t2
}

define i32 @tgt(i32 %x) {
entry:
  %t = add i32 %x, 4
  ret i32 %t
}

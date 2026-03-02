; Alive2 sample: fold (x+1)+2 into x+3

define i32 @src(i32 %x) {
entry:
  %t1 = add i32 %x, 1
  %t2 = add i32 %t1, 2
  ret i32 %t2
}

define i32 @tgt(i32 %x) {
entry:
  %t = add i32 %x, 3
  ret i32 %t
}

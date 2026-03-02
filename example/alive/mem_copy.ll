; Alive2 sample: copy value from q into p, simplifying final value

define void @src(i32* %p, i32* %q, i32 %x, i32 %y) {
entry:
  store i32 %x, i32* %p, align 4
  store i32 %y, i32* %q, align 4
  %tmp = load i32, i32* %q, align 4
  store i32 %tmp, i32* %p, align 4
  ret void
}

define void @tgt(i32* %p, i32* %q, i32 %x, i32 %y) {
entry:
  store i32 %y, i32* %q, align 4
  store i32 %y, i32* %p, align 4
  ret void
}

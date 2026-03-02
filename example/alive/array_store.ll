; Alive2 sample: two writes to same element, last write wins

define i32 @src(i32* %a, i32 %x, i32 %y, i32 %idx) {
entry:
  %p = getelementptr inbounds i32, i32* %a, i32 %idx
  store i32 %x, i32* %p, align 4
  store i32 %y, i32* %p, align 4
  %r = load i32, i32* %p, align 4
  ret i32 %r
}

define i32 @tgt(i32* %a, i32 %x, i32 %y, i32 %idx) {
entry:
  %p = getelementptr inbounds i32, i32* %a, i32 %idx
  store i32 %y, i32* %p, align 4
  %r = load i32, i32* %p, align 4
  ret i32 %r
}

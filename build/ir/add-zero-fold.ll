; Rule: add-zero-fold
; Source pattern: $X + 0
define i32 @src(i32 %x) {
entry:
  %0 = add i32 %x, 0
  ret i32 %0
}


; Rule: add-zero-fold
; Target after folding add-zero
define i32 @tgt(i32 %x) {
entry:
  ret i32 %x
}


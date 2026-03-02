; Rule: bad-branch-true-wrong (manual)
; Intent: Alive2 should reject replacing always-true branch with else arm

define i32 @src(i32 %A, i32 %B) {
entry:
  br i1 true, label %then, label %else
then:
  ret i32 %A
else:
  ret i32 %B
}

define i32 @tgt(i32 %A, i32 %B) {
entry:
  ret i32 %B
}

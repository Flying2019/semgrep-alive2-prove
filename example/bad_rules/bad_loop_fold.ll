; Rule: bad-loop-fold (manual)
; Intent: Incorrectly collapse counted addition loop without guarding N<=0/poison; Alive2 should reject

define i32 @src(i32 %A, i32 %N, i32 %X) {
entry:
  br label %loop
loop:
  %i = phi i32 [0, %entry], [%i.next, %body]
  %acc.cur = phi i32 [%A, %entry], [%acc.next, %body]
  %cmp = icmp slt i32 %i, %N
  br i1 %cmp, label %body, label %exit
body:
  %acc.next = add i32 %acc.cur, %X
  %i.next = add i32 %i, 1
  br label %loop
exit:
  ret i32 %acc.cur
}

define i32 @tgt(i32 %A, i32 %N, i32 %X) {
entry:
  %prod = mul i32 %N, %X
  %res = add i32 %A, %prod
  ret i32 %res
}

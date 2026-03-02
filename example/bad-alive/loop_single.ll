; Bad Alive2 sample: loop folded without guarding n<=0/poison

define i32 @src(i32 %x, i32 %n, i32 %m) {
entry:
  br label %loop
loop:
  %i = phi i32 [0, %entry], [%i.next, %body]
  %acc = phi i32 [%x, %entry], [%acc.next, %body]
  %cmp = icmp slt i32 %i, %n
  br i1 %cmp, label %body, label %exit
body:
  %acc.next = add i32 %acc, %m
  %i.next = add i32 %i, 1
  br label %loop
exit:
  ret i32 %acc
}

define i32 @tgt(i32 %x, i32 %n, i32 %m) {
entry:
  %prod = mul i32 %n, %m
  %res = add i32 %x, %prod
  ret i32 %res
}

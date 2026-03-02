; Bad Alive2 sample: double loop collapsed without zero-iteration guarding

define i32 @src(i32 %x, i32 %n, i32 %k, i32 %m) {
entry:
  br label %outer

outer:
  %i = phi i32 [0, %entry], [%i.next, %outer.inc]
  %acc.o = phi i32 [%x, %entry], [%acc.after, %outer.inc]
  %cmp.i = icmp slt i32 %i, %n
  br i1 %cmp.i, label %inner.entry, label %exit

inner.entry:
  br label %inner

inner:
  %j = phi i32 [0, %inner.entry], [%j.next, %inner.body]
  %acc = phi i32 [%acc.o, %inner.entry], [%acc.next, %inner.body]
  %cmp.j = icmp slt i32 %j, %k
  br i1 %cmp.j, label %inner.body, label %inner.exit

inner.body:
  %acc.next = add i32 %acc, %m
  %j.next = add i32 %j, 1
  br label %inner

inner.exit:
  %acc.after = add i32 %acc, 0
  br label %outer.inc

outer.inc:
  %i.next = add i32 %i, 1
  br label %outer

exit:
  ret i32 %acc.o
}

define i32 @tgt(i32 %x, i32 %n, i32 %k, i32 %m) {
entry:
  %prod = mul i32 %n, %k
  %prod2 = mul i32 %prod, %m
  %res = add i32 %x, %prod2
  ret i32 %res
}

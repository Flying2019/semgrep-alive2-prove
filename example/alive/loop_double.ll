; Alive2 sample: double counted loop accumulating m, collapsed to product

define i32 @src(i32 %x, i32 %n, i32 %k, i32 %m) {
entry:
  br label %outer
outer:
  %i = phi i32 [0, %entry], [%i.next, %inner.exit]
  %acc.o = phi i32 [%x, %entry], [%acc.out, %inner.exit]
  %cmp.i = icmp slt i32 %i, %n
  br i1 %cmp.i, label %outer.body, label %outer.exit
outer.body:
  br label %inner
inner:
  %j = phi i32 [0, %outer.body], [%j.next, %inner.body]
  %acc = phi i32 [%acc.o, %outer.body], [%acc.next, %inner.body]
  %cmp.j = icmp slt i32 %j, %k
  br i1 %cmp.j, label %inner.body, label %inner.exit
inner.body:
  %acc.next = add i32 %acc, %m
  %j.next = add i32 %j, 1
  br label %inner
inner.exit:
  %acc.out = add i32 %acc, 0
  %i.next = add i32 %i, 1
  br label %outer
outer.exit:
  ret i32 %acc.o
}

define i32 @tgt(i32 %x, i32 %n, i32 %k, i32 %m) {
entry:
  %no.iter.n = icmp sle i32 %n, 0
  %k.safe = select i1 %no.iter.n, i32 0, i32 %k
  %no.iter.k = icmp sle i32 %k.safe, 0
  %no.iter = or i1 %no.iter.n, %no.iter.k
  %m.safe = select i1 %no.iter, i32 0, i32 %m
  %prod = mul i32 %n, %k.safe
  %prod2 = mul i32 %prod, %m.safe
  %res = add i32 %x, %prod2
  ret i32 %res
}

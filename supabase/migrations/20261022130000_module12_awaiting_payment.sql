-- Module 12 S1: an order waits here, unseen by the kitchen, until it's paid.
-- Its own file: Postgres can't use an enum value in the transaction that adds it,
-- and the next migration uses it everywhere.

alter type public.order_status add value if not exists 'AWAITING_PAYMENT' before 'PENDING';

-- Scenario 1 (CG-S10-ATW-024, Prompt 243): concurrent app.post_inventory_movement
-- calls against a SHARED balance dimension -- empirically proves ATW-015's own
-- SELECT ... FOR UPDATE row-lock safety claim (docs/build-log/phase-05/ATW-015.md,
-- ISS-2026-014) under real concurrent multi-session load, not just reasoned-about.
--
-- __TENANT_ID__/__WAREHOUSE_ID__/__ACCOUNT_ALPHA_ID__/__HOT_ITEM_ID__/
-- __HOT_LOCATION_ID__/__ADMIN_ACTOR_ID__ are literal placeholder tokens, rendered
-- by scripts/load-tests/run.sh (a plain `sed` substitution into a temp copy
-- before invoking pgbench) from the seed's own captured real ids -- NOT
-- pgbench's own `:'var'`/`-D` quoted-variable substitution, which this
-- environment's pgbench 16.13 build was directly, reproducibly found NOT to
-- apply (`select :'foo' as x;` with `-D foo=bar` sends the literal, unsubstituted
-- text `:'foo'` to the server and errors -- confirmed with `--debug` showing the
-- raw unsubstituted query on the wire, across simple/extended/prepared query
-- modes alike). Plain unquoted `:foo` numeric substitution DID work in the same
-- environment, but every value this scenario needs is a uuid, which needs real
-- quoting -- sed pre-rendering sidesteps the issue entirely and is simpler.
--
-- Each transaction posts a real, idempotency-keyed adjustment of -1 unit against
-- the single seeded "hot" balance (on_hand = 1,000,000, comfortably never
-- reachable at this load scenario's own transaction volume). A unique
-- idempotency_key per call (clock_timestamp()+random(), computed server-side) means
-- every call is a genuinely new, accepted movement -- never an idempotent replay
-- masking a lost update.
select app.post_inventory_movement(
  '__TENANT_ID__', '__WAREHOUSE_ID__', 'adjustment', 'manual', null,
  'idem-loadtest-hotmove-' || md5(clock_timestamp()::text || random()::text || pg_backend_pid()::text),
  'load test concurrent adjustment',
  jsonb_build_array(jsonb_build_object(
    'owner_account_id', '__ACCOUNT_ALPHA_ID__', 'item_master_id', '__HOT_ITEM_ID__', 'location_id', '__HOT_LOCATION_ID__',
    'uom_code', 'PCS', 'signed_quantity', -1, 'status', 'on_hand'
  )),
  '__ADMIN_ACTOR_ID__', 'loadtest-pgbench'
);

# RPO / RTO measurement design

Evidence in this file: **DOCUMENTED** procedure. No MEASURED values yet.

Do not copy vendor “2 minute WAL” or “4 hour restore” into the verdict.

---

## RPO

```
T0 = confirmed backup/recovery point exists
     (PITR latest restore point, or dump file mtime)

T1 = write synthetic critical transaction
     organization_settings key = dr.rpo_probe
     value = { id: "DR_FIXTURE_RPO_PROBE", written_at: <timestamptz> }
     plus optional posted journal line with metadata.dr_fixture = DR_FIXTURE_RPO_TXN

T2 = simulated disaster (declare; isolate drill primary)

T3 = restored environment available (DB + Storage + app)

latest_recovered_timestamp = written_at of DR_FIXTURE_RPO_PROBE if row exists
                           else last recovered fixture timestamp
                           else NULL (RPO fail)

MEASURED_RPO_MINUTES =
  (latest_committed_source_timestamp - latest_recovered_timestamp)
  in minutes, no rounding that flips PASS/FAIL

RPO_TARGET_PASS = MEASURED_RPO_MINUTES <= 5
```

If the probe row is missing, treat recovered timestamp as T0 (or null) and MEASURED_RPO as T1−T0 (usually ≫ 5 min) → FAIL.

Required evidence: timestamps (UTC), transaction/fixture IDs, recovered IDs. Class **MEASURED** only after restore.

---

## RTO

Clock starts at **disaster declaration**, not at “Postgres is up”.

```
T_DISASTER = T2

T_SERVICE_RECOVERED = time when ALL are true:
  - database restored (schema + synthetic rows)
  - storage restored (DR_FIXTURE object hash match)
  - app connected (health + Auth login)
  - tenant isolation (cross-tenant probes)
  - Golden Flow after restore PASS

MEASURED_RTO_MINUTES = T_SERVICE_RECOVERED - T_DISASTER
RTO_TARGET_PASS = MEASURED_RTO_MINUTES <= 240
```

Do not stop the clock when PostgreSQL accepts connections.

---

## Clock source

Single NTP-synced operator machine; ISO-8601 UTC in `DR-TIMELINE.json`.

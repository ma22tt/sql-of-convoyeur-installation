This project has been created by ma2t.

# Entrepot SQL

## Description

Entrepot SQL is a small database learning project. The goal is to practice the fundamentals of relational databases — tables and types, primary and foreign keys, constraints, joins, aggregates and transactions — by giving a permanent memory to the conveyor installation modelled in the `Installation` TypeScript class of a companion project.

The same model is written twice, once for each engine, so the two can be read side by side:

- **sqlite/**: the file-based version. The whole database is a single `entrepot.db` file, nothing runs in the background. This is the one to read first.
- **postgres/**: the server version, running in a Docker container. Same tables, same questions, but written for a real database server listening on a port.

Both folders hold the same three files, on purpose:

- **01_schema.sql**: the structure. Three tables (`machines`, `charges`, `mouvements`) and the constraints that enforce the domain rules — a load can only ever be `posee`, `en_transit` or `retiree`, a machine carries at most one load, and each kind of movement has its own shape. These constraints replace the `throw new Error(...)` guards of the TypeScript class: the database refuses an impossible row even when the program sending it has a bug.
- **02_donnees.sql**: a fixed starting scenario. Five machines, four pallets and eleven movements, loaded inside a transaction. One pallet left its machine 45 seconds ago and never arrived — it is the lost load the queries are meant to find.
- **03_requetes.sql**: the questions a real control system asks its database, in numbered blocks from `SELECT` up to `ROLLBACK`. Where are the pallets, which ones are in transit, and which one has been gone for more than 30 seconds without arriving.

The third table, `mouvements`, is what the TypeScript class does not have. The class overwrites its state on every call, so the past is lost; a database keeps the whole history, and that history is what makes the lost-load question answerable at all.

## How it works

```
          .env                 (credentials, never committed)
            │
            ▼
   docker-compose.yml  ──────────────────┐
            │                            │
            ▼                            ▼
    postgres/01_schema.sql        postgres container
    postgres/02_donnees.sql   ──▶  (runs them at first boot)
            │                            │
            │                            ▼
    postgres/03_requetes.sql  ──▶       psql            ──▶  terminal output
                                  (via ./pg.sh)


    sqlite/01_schema.sql
    sqlite/02_donnees.sql     ──▶  sqlite/entrepot.db   ──▶  terminal output
    sqlite/03_requetes.sql         (via ./run.sh)
```

A `.sql` file does nothing on its own — it is inert text until an engine reads it. On the SQLite side, the `sqlite3` command opens the database file, applies the file and exits; no process stays alive. On the PostgreSQL side, a server keeps running inside the container, listens on port 5432 and answers connections, which is why it shows up in Docker Desktop and the SQLite version never will.

`./run.sh` and `./pg.sh` exist only to hand those files to the right engine. Both rebuild the data before running the queries, so every run starts from the same state and prints the same thing.

## Instructions

You need SQLite for the first version, and Docker for the second.

```
./run.sh                 # SQLite: rebuild and run every query
./run.sh shell           # SQLite: type your own queries

cp .env.example .env     # set a password first
./pg.sh up               # start the PostgreSQL server
./pg.sh requetes         # run every query against it
./pg.sh shell            # type your own queries
./pg.sh down             # stop it, keeping the data
```

## Design choices

**Constraints in the schema rather than checks in the application.** Every rule the TypeScript class enforces with a guard clause is written as a `CHECK` here, including the three-way agreement between `etat`, `machine_id` and `destination_id`. An application check only protects the rows that application writes; a constraint protects the table from every client, including a hand-typed `INSERT` at 2am. The database stays correct even when the code around it is wrong.

**A partial unique index for "one load per machine", rather than a plain `UNIQUE`.** A plain unique index on `machine_id` would work here too: both SQLite and PostgreSQL treat two `NULL`s as distinct, so any number of loads can be in transit with a null `machine_id` without colliding. The partial index is kept for two other reasons. It states which rows the rule covers instead of leaning on a `NULL` convention that is not universal — SQL Server treats two `NULL`s as equal, and PostgreSQL 15 made the behaviour selectable with `NULLS NOT DISTINCT` — and it only indexes the rows that can actually collide, leaving in-transit and removed loads out of it.

**A separate `mouvements` table instead of extra columns on `charges`.** Storing a `parti_a` timestamp on the load itself would answer "is it late" but erase the previous trip every time. A history table keeps every event, which is what makes the average trip duration and the lost-load detection possible from the same data.

**No `charge` column on `machines`.** The link between a machine and its load is stored once, on the load. Writing it on both sides would allow the two to disagree, and nothing in SQL would keep them in step.

**An `ENUM` type in PostgreSQL, a `CHECK ... IN (...)` in SQLite.** The PostgreSQL enum is the closest equivalent to the `type Etat = "posee" | "en_transit" | "retiree"` union: the column cannot physically hold anything else, and comparing it against an invalid string is an error rather than a silently empty result. SQLite has no such type, so the same guarantee is written as a check constraint.

**Credentials in `.env`, and the port bound to `127.0.0.1`.** The obvious `"5432:5432"` in a compose file publishes the port on every network interface, so anyone on the same Wi-Fi can reach the database; binding it to `127.0.0.1` keeps it reachable from this machine only. The password lives in `.env`, which is git-ignored, with `.env.example` committed in its place to document the variables without their values.

**A pinned image tag (`postgres:18.0-alpine`).** A floating tag like `postgres:18` quietly changes under you, so two machines cloning this repository a month apart can end up on different versions. Pinning makes the environment reproducible.

**Rebuilding the data before every query run.** Block 9 commits a transaction that moves a pallet, which would change what block 3 prints on the next run. Reloading first makes the output stable and comparable between the two engines.

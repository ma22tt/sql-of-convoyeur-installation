-- les tables. lance par ./run.sh

PRAGMA foreign_keys = ON;   -- sinon sqlite ignore les cles etrangeres

DROP TABLE IF EXISTS mouvements;
DROP TABLE IF EXISTS charges;
DROP TABLE IF EXISTS machines;


-- les 5 postes
CREATE TABLE machines (
    id   INTEGER PRIMARY KEY,
    nom  TEXT NOT NULL UNIQUE,
    CHECK (length(trim(nom)) > 0)
);


-- les palettes.
-- pas de colonne "charge" ici, c'est la charge qui sait ou elle est.
-- dupliquer le lien des deux cotes finit toujours par se contredire.
CREATE TABLE charges (
    id             INTEGER PRIMARY KEY,

    -- meme chose que : type Etat = "posee" | "en_transit" | "retiree"
    etat           TEXT NOT NULL
                   CHECK (etat IN ('posee', 'en_transit', 'retiree')),

    machine_id     INTEGER REFERENCES machines(id) ON DELETE RESTRICT,   -- ou elle est posee
    destination_id INTEGER REFERENCES machines(id) ON DELETE RESTRICT,   -- ou elle va

    -- remplace les throw du TypeScript.
    -- posee : quelque part, va nulle part. en_transit : l'inverse. retiree : ni l'un ni l'autre
    CHECK (
        (etat = 'posee'      AND machine_id IS NOT NULL AND destination_id IS NULL)
     OR (etat = 'en_transit' AND machine_id IS NULL     AND destination_id IS NOT NULL)
     OR (etat = 'retiree'    AND machine_id IS NULL     AND destination_id IS NULL)
    ),

    -- pas de trajet vers la machine ou on est deja
    CHECK (machine_id IS NULL OR destination_id IS NULL OR machine_id <> destination_id)
);

-- une machine porte au plus une charge.
-- le WHERE est obligatoire. sans lui, deux palettes en transit auraient
-- toutes les deux machine_id a NULL et la deuxieme serait refusee
CREATE UNIQUE INDEX idx_une_charge_par_machine
    ON charges (machine_id)
    WHERE machine_id IS NOT NULL;


-- l'historique. la classe TypeScript ne l'a pas : elle ecrase l'etat
-- precedent a chaque appel. sans cette table, impossible de savoir
-- depuis quand une palette a disparu
CREATE TABLE mouvements (
    id                 INTEGER PRIMARY KEY,
    charge_id          INTEGER NOT NULL REFERENCES charges(id) ON DELETE CASCADE,
    type               TEXT NOT NULL
                       CHECK (type IN ('depot', 'depart', 'arrivee', 'retrait')),
    machine_depart_id  INTEGER REFERENCES machines(id) ON DELETE RESTRICT,
    machine_arrivee_id INTEGER REFERENCES machines(id) ON DELETE RESTRICT,
    horodatage         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- chaque type a sa forme. un depot arrive sans venir de nulle part,
    -- un retrait part sans aller nulle part
    CHECK (
        (type = 'depot'   AND machine_depart_id IS NULL     AND machine_arrivee_id IS NOT NULL)
     OR (type = 'depart'  AND machine_depart_id IS NOT NULL AND machine_arrivee_id IS NOT NULL)
     OR (type = 'arrivee' AND machine_depart_id IS NULL     AND machine_arrivee_id IS NOT NULL)
     OR (type = 'retrait' AND machine_depart_id IS NOT NULL AND machine_arrivee_id IS NULL)
    )
);

CREATE INDEX idx_mouvements_charge ON mouvements (charge_id, horodatage);

-- le jeu de depart. lance par ./run.sh

PRAGMA foreign_keys = ON;

-- tout ou rien. une erreur en route et rien n'est ecrit,
-- plutot qu'un chargement a moitie fait
BEGIN TRANSACTION;

DELETE FROM mouvements;
DELETE FROM charges;
DELETE FROM machines;

INSERT INTO machines (id, nom) VALUES
    (1, 'M1'), (2, 'M2'), (3, 'M3'), (4, 'M4'), (5, 'M5');

-- 101 posee sur M1
-- 102 en transit vers M5
-- 103 en transit vers M4, partie depuis 45 s : c'est la perdue
-- 104 retiree
INSERT INTO charges (id, etat, machine_id, destination_id) VALUES
    (101, 'posee',      1,    NULL),
    (102, 'en_transit', NULL, 5),
    (103, 'en_transit', NULL, 4),
    (104, 'retiree',    NULL, NULL);

-- les dates sont calculees au moment de l'insertion.
-- si tu laisses la base vivre une heure, la 102 franchira le seuil
-- des 30 s elle aussi. relance ./run.sh pour repartir propre
INSERT INTO mouvements (charge_id, type, machine_depart_id, machine_arrivee_id, horodatage) VALUES
    (101, 'depot',   NULL, 5, datetime('now', '-12 minutes')),
    (101, 'depart',  5,    1, datetime('now', '-11 minutes')),
    (101, 'arrivee', NULL, 1, datetime('now', '-11 minutes', '+15 seconds')),

    (104, 'depot',   NULL, 2, datetime('now', '-9 minutes')),
    (104, 'depart',  2,    4, datetime('now', '-8 minutes')),
    (104, 'arrivee', NULL, 4, datetime('now', '-8 minutes', '+10 seconds')),

    (102, 'depot',   NULL, 3, datetime('now', '-6 minutes')),
    (103, 'depot',   NULL, 2, datetime('now', '-5 minutes')),
    (104, 'retrait', 4,    NULL, datetime('now', '-2 minutes')),

    -- la 103 part et n'arrive jamais. aucune ligne arrivee derriere
    (103, 'depart',  2,    4, datetime('now', '-45 seconds')),
    (102, 'depart',  3,    5, datetime('now', '-4 seconds'));

COMMIT;

SELECT 'machines : '  || COUNT(*) FROM machines
UNION ALL SELECT 'charges : '   || COUNT(*) FROM charges
UNION ALL SELECT 'mouvements : '|| COUNT(*) FROM mouvements;

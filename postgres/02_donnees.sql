-- le jeu de depart, version postgres.
-- 101 posee sur M1, 102 en transit vers M5, 103 en transit vers M4
-- depuis 45 s donc perdue, 104 retiree

BEGIN;

DELETE FROM mouvements;
DELETE FROM charges;
DELETE FROM machines;

INSERT INTO machines (id, nom) VALUES
    (1, 'M1'), (2, 'M2'), (3, 'M3'), (4, 'M4'), (5, 'M5');

INSERT INTO charges (id, etat, machine_id, destination_id) VALUES
    (101, 'posee',      1,    NULL),
    (102, 'en_transit', NULL, 5),
    (103, 'en_transit', NULL, 4),
    (104, 'retiree',    NULL, NULL);

-- sqlite : datetime('now', '-45 seconds')
INSERT INTO mouvements (charge_id, type, machine_depart_id, machine_arrivee_id, horodatage) VALUES
    (101, 'depot',   NULL, 5, now() - interval '12 minutes'),
    (101, 'depart',  5,    1, now() - interval '11 minutes'),
    (101, 'arrivee', NULL, 1, now() - interval '11 minutes' + interval '15 seconds'),

    (104, 'depot',   NULL, 2, now() - interval '9 minutes'),
    (104, 'depart',  2,    4, now() - interval '8 minutes'),
    (104, 'arrivee', NULL, 4, now() - interval '8 minutes' + interval '10 seconds'),

    (102, 'depot',   NULL, 3, now() - interval '6 minutes'),
    (103, 'depot',   NULL, 2, now() - interval '5 minutes'),
    (104, 'retrait', 4,    NULL, now() - interval '2 minutes'),

    -- la 103 part et n'arrive jamais
    (103, 'depart',  2,    4, now() - interval '45 seconds'),
    (102, 'depart',  3,    5, now() - interval '4 seconds');

-- les id ont ete donnes a la main, donc on recale les compteurs.
-- sans ca le prochain insert sans id repart de 1 et se cogne a la cle primaire
SELECT setval(pg_get_serial_sequence('machines',   'id'), (SELECT MAX(id) FROM machines));
SELECT setval(pg_get_serial_sequence('charges',    'id'), (SELECT MAX(id) FROM charges));
SELECT setval(pg_get_serial_sequence('mouvements', 'id'), (SELECT MAX(id) FROM mouvements));

COMMIT;

SELECT 'machines : '   || COUNT(*) FROM machines
UNION ALL SELECT 'charges : '    || COUNT(*) FROM charges
UNION ALL SELECT 'mouvements : ' || COUNT(*) FROM mouvements;

-- les memes questions, version postgres. lance par ./pg.sh requetes
-- les lignes qui commencent par un antislash sont des commandes psql,
-- pas du sql

\pset border 2
\pset linestyle unicode

\echo '--- 1. toutes les palettes ---'
SELECT id, etat, machine_id, destination_id
FROM charges
ORDER BY id DESC;

\echo '--- 1b. celles encore dans l installation ---'
SELECT id, etat
FROM charges
WHERE etat <> 'retiree'
ORDER BY etat, id;


\echo '--- 2. ou sont les palettes posees ---'
SELECT c.id AS palette, m.nom AS machine
FROM charges AS c
JOIN machines AS m ON m.id = c.machine_id
ORDER BY m.nom;


-- sqlite : strftime. ici soustraire deux dates donne un interval,
-- et EXTRACT(EPOCH FROM ...) le passe en secondes.
-- DISTINCT ON garde une seule ligne par palette, la premiere du ORDER BY.
-- il impose que le tri commence par ses colonnes, d'ou la sous-requete
-- exterieure pour retrier par duree ensuite
\echo '--- 3. en transit, depuis combien de temps ---'
SELECT * FROM (
    SELECT DISTINCT ON (c.id)
        c.id    AS palette,
        dep.nom AS vers,
        ROUND(EXTRACT(EPOCH FROM (now() - m.horodatage)))::int AS secondes
    FROM charges AS c
    JOIN machines   AS dep ON dep.id = c.destination_id
    JOIN mouvements AS m   ON m.charge_id = c.id AND m.type = 'depart'
    WHERE c.etat = 'en_transit'
    ORDER BY c.id, m.horodatage DESC
) AS en_transit
ORDER BY secondes DESC;


-- LEFT JOIN garde toutes les machines, meme vides.
-- :: est le cast de postgres, plus court que CAST(... AS TEXT)
\echo '--- 4. les 5 machines, occupees ou libres ---'
SELECT m.nom AS machine, COALESCE(c.id::text, 'libre') AS contenu
FROM machines AS m
LEFT JOIN charges AS c ON c.machine_id = m.id
ORDER BY m.id;


\echo '--- 5. combien de palettes par etat ---'
SELECT etat, COUNT(*) AS nombre
FROM charges
GROUP BY etat
ORDER BY nombre DESC;

-- COUNT(mv.id) et pas COUNT(*), sinon une machine sans mouvement afficherait 1
\echo '--- 5b. activite de chaque machine ---'
SELECT m.nom AS machine, COUNT(mv.id) AS mouvements
FROM machines AS m
LEFT JOIN mouvements AS mv
       ON mv.machine_depart_id = m.id OR mv.machine_arrivee_id = m.id
GROUP BY m.id, m.nom
ORDER BY mouvements DESC, m.nom;


-- WHERE filtre des lignes, HAVING filtre des paquets
\echo '--- 6. palettes avec au moins 3 mouvements ---'
SELECT charge_id AS palette, COUNT(*) AS mouvements
FROM mouvements
GROUP BY charge_id
HAVING COUNT(*) >= 3
ORDER BY mouvements DESC;


\echo '--- 7. duree des trajets termines ---'
SELECT
    d.charge_id AS palette,
    ROUND(EXTRACT(EPOCH FROM (a.horodatage - d.horodatage)))::int AS secondes
FROM mouvements AS d
JOIN mouvements AS a
      ON a.charge_id = d.charge_id
     AND a.type = 'arrivee'
     AND a.horodatage > d.horodatage
WHERE d.type = 'depart'
ORDER BY secondes;

\echo '--- 7b. la moyenne ---'
SELECT ROUND(AVG(secondes), 1) AS duree_moyenne_s
FROM (
    SELECT EXTRACT(EPOCH FROM (a.horodatage - d.horodatage)) AS secondes
    FROM mouvements AS d
    JOIN mouvements AS a
          ON a.charge_id = d.charge_id
         AND a.type = 'arrivee'
         AND a.horodatage > d.horodatage
    WHERE d.type = 'depart'
) AS trajets;   -- postgres exige un alias sur une sous-requete du FROM


-- le but de l'exercice. toujours en_transit, partie depuis plus de 30 s,
-- et rien d'enregistre en arrivee apres ce depart.
-- la duree s'ecrit directement en interval, sans conversion
\echo '--- 8. charges perdues, plus de 30 s sans arriver ---'
SELECT
    c.id    AS palette,
    org.nom AS partie_de,
    dst.nom AS vers,
    ROUND(EXTRACT(EPOCH FROM (now() - m.horodatage)))::int AS perdue_depuis_s
FROM charges AS c
JOIN mouvements AS m   ON m.charge_id = c.id AND m.type = 'depart'
JOIN machines   AS org ON org.id = m.machine_depart_id
JOIN machines   AS dst ON dst.id = m.machine_arrivee_id
WHERE c.etat = 'en_transit'
  AND m.horodatage < now() - interval '30 seconds'
  AND NOT EXISTS (
        SELECT 1 FROM mouvements AS arr
        WHERE arr.charge_id = c.id
          AND arr.type = 'arrivee'
          AND arr.horodatage > m.horodatage
  )
ORDER BY perdue_depuis_s DESC;


-- un depart, c'est 2 ecritures. BEGIN et COMMIT les rendent indivisibles
\echo '--- 9. un depart = 2 ecritures indissociables ---'
BEGIN;
    UPDATE charges
    SET etat = 'en_transit', machine_id = NULL, destination_id = 3
    WHERE id = 101 AND etat = 'posee';

    INSERT INTO mouvements (charge_id, type, machine_depart_id, machine_arrivee_id)
    VALUES (101, 'depart', 1, 3);
COMMIT;

SELECT id, etat, machine_id, destination_id FROM charges WHERE id = 101;


-- le piege. relance le bloc au-dessus une deuxieme fois : psql affiche
-- UPDATE 0 puis INSERT 0 1. la palette n'est plus posee donc l'update ne
-- touche rien, mais le mouvement s'ecrit quand meme. le commit valide un
-- depart fantome.
-- une transaction protege d'une panne, pas d'une logique fausse.
-- cote api : lire rowCount apres l'update, rollback si c'est 0.
-- en sql pur : chainer les deux ordres avec WITH et RETURNING
\echo '--- 9b. le piege, une transaction ne rend pas ta logique juste ---'
WITH avant AS (
    -- l'etat avant modification. seule facon de connaitre l'origine,
    -- que l'update va effacer
    SELECT id, machine_id AS origine
    FROM charges
    WHERE id = 104 AND etat = 'posee'
),
maj AS (
    UPDATE charges AS c
    SET etat = 'en_transit', machine_id = NULL, destination_id = 3
    FROM avant
    WHERE c.id = avant.id
    RETURNING c.id
)
INSERT INTO mouvements (charge_id, type, machine_depart_id, machine_arrivee_id)
SELECT avant.id, 'depart', avant.origine, 3
FROM avant
JOIN maj ON maj.id = avant.id;

\echo 'la 104 est retiree, pas posee. 0 ligne inseree, pas de fantome.'


\echo '--- 9c. rollback, annuler un lot entier ---'
BEGIN;
    UPDATE charges SET etat = 'retiree', destination_id = NULL WHERE id = 102;
ROLLBACK;

\echo 'la 102 doit etre encore en_transit :'
SELECT id, etat, destination_id FROM charges WHERE id = 102;


-- un serveur sait qui lui parle, un fichier sqlite non
\echo '--- 10. impossible en sqlite, voir qui est connecte ---'
SELECT pid, usename AS utilisateur, application_name AS application, state AS etat_connexion
FROM pg_stat_activity
WHERE datname = current_database();

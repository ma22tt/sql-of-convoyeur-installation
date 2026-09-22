-- les questions du systeme de pilotage. lance par ./run.sh
-- les lignes qui commencent par un point sont des commandes du shell
-- sqlite3, pas du sql

.mode box
.headers on


.print '--- 1. toutes les palettes ---'
SELECT id, etat, machine_id, destination_id
FROM charges
ORDER BY id DESC;

.print ''
.print '--- 1b. celles encore dans l installation ---'
SELECT id, etat
FROM charges
WHERE etat <> 'retiree'
ORDER BY etat, id;


-- JOIN garde uniquement les lignes qui ont un correspondant des deux
-- cotes. les palettes en transit ou retirees n'ont pas de machine,
-- donc elles disparaissent du resultat
.print ''
.print '--- 2. ou sont les palettes posees ---'
SELECT c.id AS palette, m.nom AS machine
FROM charges AS c
JOIN machines AS m ON m.id = c.machine_id
ORDER BY m.nom;


-- strftime('%s', date) donne des secondes, donc la difference est une duree.
-- la sous-requete MAX evite un doublon : une palette qui a deja voyage
-- a plusieurs lignes depart, et sans ca elle sortirait une fois par depart
.print ''
.print '--- 3. en transit, depuis combien de temps ---'
SELECT
    c.id    AS palette,
    dep.nom AS vers,
    CAST(strftime('%s','now') - strftime('%s', m.horodatage) AS INTEGER) AS secondes
FROM charges AS c
JOIN machines   AS dep ON dep.id = c.destination_id
JOIN mouvements AS m   ON m.charge_id = c.id AND m.type = 'depart'
WHERE c.etat = 'en_transit'
  AND m.horodatage = (
        SELECT MAX(d.horodatage) FROM mouvements AS d
        WHERE d.charge_id = c.id AND d.type = 'depart'
  )
ORDER BY secondes DESC;


-- LEFT JOIN garde toutes les machines, meme vides. c'est la difference
-- avec le bloc 2. equivalent de la methode etat()
.print ''
.print '--- 4. les 5 machines, occupees ou libres ---'
SELECT
    m.nom AS machine,
    COALESCE(CAST(c.id AS TEXT), 'libre') AS contenu
FROM machines AS m
LEFT JOIN charges AS c ON c.machine_id = m.id
ORDER BY m.id;


-- GROUP BY fait des paquets, COUNT compte dedans
.print ''
.print '--- 5. combien de palettes par etat ---'
SELECT etat, COUNT(*) AS nombre
FROM charges
GROUP BY etat
ORDER BY nombre DESC;

-- COUNT(mv.id) et pas COUNT(*) : le LEFT JOIN fabrique une ligne vide
-- pour une machine sans mouvement, et COUNT(*) la compterait quand meme
.print ''
.print '--- 5b. activite de chaque machine ---'
SELECT m.nom AS machine, COUNT(mv.id) AS mouvements
FROM machines AS m
LEFT JOIN mouvements AS mv
       ON mv.machine_depart_id = m.id OR mv.machine_arrivee_id = m.id
GROUP BY m.id, m.nom
ORDER BY mouvements DESC, m.nom;


-- WHERE filtre des lignes, HAVING filtre des paquets.
-- WHERE COUNT(*) >= 3 serait une erreur, les paquets n'existent pas encore
.print ''
.print '--- 6. palettes avec au moins 3 mouvements ---'
SELECT charge_id AS palette, COUNT(*) AS mouvements
FROM mouvements
GROUP BY charge_id
HAVING COUNT(*) >= 3
ORDER BY mouvements DESC;


-- on relie la table a elle-meme, alias d et a, pour coller chaque
-- depart a l'arrivee qui suit
.print ''
.print '--- 7. duree des trajets termines ---'
SELECT
    d.charge_id AS palette,
    strftime('%s', a.horodatage) - strftime('%s', d.horodatage) AS secondes
FROM mouvements AS d
JOIN mouvements AS a
      ON a.charge_id = d.charge_id
     AND a.type = 'arrivee'
     AND a.horodatage > d.horodatage
WHERE d.type = 'depart'
ORDER BY secondes;

.print ''
.print '--- 7b. la moyenne ---'
SELECT ROUND(AVG(secondes), 1) AS duree_moyenne_s
FROM (
    SELECT strftime('%s', a.horodatage) - strftime('%s', d.horodatage) AS secondes
    FROM mouvements AS d
    JOIN mouvements AS a
          ON a.charge_id = d.charge_id
         AND a.type = 'arrivee'
         AND a.horodatage > d.horodatage
    WHERE d.type = 'depart'
);


-- le but de l'exercice. trois conditions en meme temps :
-- toujours en_transit, partie depuis plus de 30 s, et aucune arrivee
-- enregistree apres ce depart.
-- NOT EXISTS est vrai quand la sous-requete ne ramene rien
.print ''
.print '--- 8. charges perdues, plus de 30 s sans arriver ---'
SELECT
    c.id    AS palette,
    org.nom AS partie_de,
    dst.nom AS vers,
    CAST(strftime('%s','now') - strftime('%s', m.horodatage) AS INTEGER) AS perdue_depuis_s
FROM charges AS c
JOIN mouvements AS m   ON m.charge_id = c.id AND m.type = 'depart'
JOIN machines   AS org ON org.id = m.machine_depart_id
JOIN machines   AS dst ON dst.id = m.machine_arrivee_id
WHERE c.etat = 'en_transit'
  AND strftime('%s','now') - strftime('%s', m.horodatage) > 30
  AND NOT EXISTS (
        SELECT 1 FROM mouvements AS arr
        WHERE arr.charge_id = c.id
          AND arr.type = 'arrivee'
          AND arr.horodatage > m.horodatage
  )
ORDER BY perdue_depuis_s DESC;

-- meme resultat autrement. on tente de coller une arrivee et on garde
-- seulement les echecs. ca s'appelle une anti-jointure
.print ''
.print '--- 8b. la meme question avec un LEFT JOIN ---'
SELECT
    c.id AS palette,
    CAST(strftime('%s','now') - strftime('%s', m.horodatage) AS INTEGER) AS perdue_depuis_s
FROM charges AS c
JOIN mouvements AS m ON m.charge_id = c.id AND m.type = 'depart'
LEFT JOIN mouvements AS arr
       ON arr.charge_id = c.id
      AND arr.type = 'arrivee'
      AND arr.horodatage > m.horodatage
WHERE c.etat = 'en_transit'
  AND arr.id IS NULL
  AND strftime('%s','now') - strftime('%s', m.horodatage) > 30;


-- un depart, c'est 2 ecritures. si le serveur tombe entre les deux,
-- la base garde une palette en transit sans trace de son depart.
-- elle devient introuvable
.print ''
.print '--- 9. un depart = 2 ecritures indissociables ---'
BEGIN TRANSACTION;
    UPDATE charges
    SET etat = 'en_transit', machine_id = NULL, destination_id = 3
    WHERE id = 101 AND etat = 'posee';

    INSERT INTO mouvements (charge_id, type, machine_depart_id, machine_arrivee_id)
    VALUES (101, 'depart', 1, 3);
COMMIT;

SELECT id, etat, machine_id, destination_id FROM charges WHERE id = 101;

-- apres un ROLLBACK la base revient exactement a son etat d'avant le BEGIN
.print ''
.print '--- 9b. rollback, annuler un lot entier ---'
BEGIN TRANSACTION;
    UPDATE charges SET etat = 'retiree', destination_id = NULL WHERE id = 102;
ROLLBACK;

.print 'la 102 doit etre encore en_transit :'
SELECT id, etat, destination_id FROM charges WHERE id = 102;


-- pour la suite : les blocs 4, 1, 3 et 8 sont les futures routes
-- de l'api, et le bloc 9 est ce que fera POST /charges/:id/partir

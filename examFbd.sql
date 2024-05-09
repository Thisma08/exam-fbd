-- 1
CREATE USER 'user_juin2023'@'localhost' IDENTIFIED BY 'juin2023';
GRANT CREATE TEMPORARY TABLES ON *.* TO 'user_juin2023'@'localhost';
GRANT EXECUTE ON PROCEDURE ue219_juin2023.procedure_intervention to 'user_juin2023'@'localhost';

DELIMITER |

CREATE PROCEDURE procedure_intervention(IN tech_id INT, IN intervention_date DATETIME)
BEGIN
    DECLARE tech_salaire_horaire DECIMAL(7,2);
    DECLARE tech_pourcentage DECIMAL(3,2);
    DECLARE intervention_duree TIME;
    DECLARE total_a_payer DECIMAL(10,2);
    DECLARE reduction DECIMAL(5,2);

    -- Récupération du salaire horaire et du pourcentage du technicien
    SELECT f.salaire_horaire_base, s.pourcentage 
    INTO tech_salaire_horaire, tech_pourcentage 
    FROM technicien t 
    JOIN fonction f ON t.idfonction = f.idfonction
    JOIN societe s ON t.idsociete = s.idsociete 
    WHERE t.idtech = tech_id;

    -- Calcul de la durée de l'intervention
    SET intervention_duree = TIMEDIFF(
        (SELECT date_fin_intervention FROM intervention WHERE idtech = tech_id AND date_debut_intervention = intervention_date),
        (SELECT date_debut_intervention FROM intervention WHERE idtech = tech_id AND date_debut_intervention = intervention_date)
    );

    -- Calcul du total à payer avant réductions
    SET total_a_payer = TIME_TO_SEC(intervention_duree) / 3600 * tech_salaire_horaire * tech_pourcentage;

    -- Calcul de la réduction en fonction du type de carte du client et de la date
    SELECT CASE 
        WHEN c.typecarte = 'or' THEN 0.10
        WHEN c.typecarte = 'argent' THEN 0.05
        WHEN c.typecarte = 'bronze' THEN 0.02
        ELSE 0
    END INTO reduction
    FROM intervention i
    JOIN client c ON i.idcli = c.idcli
    WHERE i.idtech = tech_id AND i.date_debut_intervention = intervention_date;

    -- Application de la réduction supplémentaire si nécessaire
    IF MONTH(intervention_date) = 4 AND reduction > 0 THEN
        SET reduction = reduction + 0.05;
    END IF;

    -- Calcul du total à payer après réductions
    SET total_a_payer = total_a_payer * (1 - reduction);

    -- Insertion des données dans la table temporaire "fact_intervention"
    CREATE TEMPORARY TABLE IF NOT EXISTS fact_intervention (
        id_client INT,
        nom_prenom_client VARCHAR(80),
        id_technicien INT,
        intitule_societe VARCHAR(50),
        date_debut_intervention DATETIME,
        duree_intervention TIME,
        total_a_payer DECIMAL(10,2)
    );

    INSERT INTO fact_intervention 
    SELECT 
        i.idcli,
        CONCAT(c.nomcli, ' ', c.prenomcli),
        i.idtech,
        s.intitulesociete,
        i.date_debut_intervention,
        intervention_duree,
        total_a_payer
    FROM intervention i
    JOIN client c ON i.idcli = c.idcli
    JOIN technicien t ON i.idtech = t.idtech
    JOIN fonction f ON t.idfonction = f.idfonction
    JOIN societe s ON t.idsociete = s.idsociete
    WHERE i.idtech = tech_id AND i.date_debut_intervention = intervention_date;

    -- Insertion du montant dans la table temporaire "montant_par_societe"
    CREATE TEMPORARY TABLE IF NOT EXISTS montant_par_societe (
        id_societe INT,
        montant_total DECIMAL(10,2)
    );

    INSERT INTO montant_par_societe (id_societe, montant_total)
    VALUES (tech_id, total_a_payer)
    ON DUPLICATE KEY UPDATE montant_total = montant_total + total_a_payer;
END|

DELIMITER ;


-- Début de la transaction
START TRANSACTION;
-- Premier appel à la procédure
CALL procedure_intervention(1, '2023-05-10 10:32:00');
-- Deuxième appel à la procédure
CALL procedure_intervention(2, '2023-05-15 11:00:00');
-- Troisième appel à la procédure
CALL procedure_intervention(3, '2023-05-12 08:30:00');
-- Quatrième appel à la procédure
CALL procedure_intervention(4, '2023-04-25 10:00:00');
-- Affichage du contenu de la table fact_intervention
SELECT * FROM fact_intervention;
-- Affichage du contenu de la table montant_par_societe
SELECT * FROM montant_par_societe;
-- Annulation des opérations effectuées dans la transaction
ROLLBACK;

-- 2
-- Création de la table permanente "nombre_clients_par_carte"
CREATE TABLE nombre_clients_par_carte (
    intitule_carte VARCHAR(15) NOT NULL,
    nombre_de_clients INT DEFAULT 0,
    PRIMARY KEY (intitule_carte)
)engine=innodb;

-- Création des TRIGGERS
DELIMITER |

CREATE TRIGGER before_client_insert
BEFORE INSERT ON client
FOR EACH ROW
BEGIN
    IF NEW.typecarte NOT IN ('or', 'argent', 'bronze') THEN
        SET NEW.typecarte = 'inconnue';
    END IF;

    -- Mise à jour de la table nombre_clients_par_carte
    IF NEW.typecarte NOT IN ('or', 'argent', 'bronze') THEN
        SET NEW.typecarte = 'inconnue';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM nombre_clients_par_carte WHERE intitule_carte = NEW.typecarte
    ) THEN
        INSERT INTO nombre_clients_par_carte (intitule_carte, nombre_de_clients) VALUES (NEW.typecarte, 1);
    ELSE
        UPDATE nombre_clients_par_carte SET nombre_de_clients = nombre_de_clients + 1 WHERE intitule_carte = NEW.typecarte;
    END IF;
END|

CREATE TRIGGER before_client_update
BEFORE UPDATE ON client
FOR EACH ROW
BEGIN
    DECLARE old_typecarte VARCHAR(15);
    
    -- Récupération de l'ancien type de carte
    SELECT typecarte INTO old_typecarte FROM client WHERE idcli = OLD.idcli;
    
    IF NEW.typecarte NOT IN ('or', 'argent', 'bronze') THEN
        IF old_typecarte IN ('or', 'argent', 'bronze') THEN
            SET NEW.typecarte = old_typecarte;
        ELSE
            SET NEW.typecarte = 'inconnue';
        END IF;
    END IF;

    -- Mise à jour de la table nombre_clients_par_carte
    IF old_typecarte != NEW.typecarte THEN
        UPDATE nombre_clients_par_carte SET nombre_de_clients = nombre_de_clients - 1 WHERE intitule_carte = old_typecarte;
        
        IF NOT EXISTS (
            SELECT 1 FROM nombre_clients_par_carte WHERE intitule_carte = NEW.typecarte
        ) THEN
            INSERT INTO nombre_clients_par_carte (intitule_carte, nombre_de_clients) VALUES (NEW.typecarte, 1);
        ELSE
            UPDATE nombre_clients_par_carte SET nombre_de_clients = nombre_de_clients + 1 WHERE intitule_carte = NEW.typecarte;
        END IF;
    END IF;
END|

DELIMITER ;

-- Création de la vue
CREATE VIEW vue_nombre_clients AS
SELECT 
    intitule_carte AS intitule_carte,
    nombre_de_clients AS nombre_de_clients,
    GROUP_CONCAT(CONCAT(prenomcli, ' ', nomcli) ORDER BY idcli SEPARATOR ', ') AS clients
FROM client
RIGHT JOIN nombre_clients_par_carte ON client.typecarte = nombre_clients_par_carte.intitule_carte
GROUP BY intitule_carte;

-- Insertion client 1
INSERT INTO client(idcli, nomcli, prenomcli, typecarte) VALUES (15, 'Potter', 'Harry', 'or');

-- Insertion client 2
INSERT INTO client(idcli, nomcli, prenomcli, typecarte) VALUES (16, 'Weasley', 'Ron', 'argile');

-- Insertion client 3
INSERT INTO client(idcli, nomcli, prenomcli, typecarte) VALUES (17, 'Granger', 'Hermione', 'argent');

-- Insertion client 4
INSERT INTO client(idcli, nomcli, prenomcli, typecarte) VALUES (18, 'Dumbledore', 'Albus', 'or');

-- Insertion client 5
INSERT INTO client(idcli, nomcli, prenomcli, typecarte) VALUES (19, 'Rogue', 'Severus', 'bronze');

-- Mise à jour client 1 - carte argent disparaît
UPDATE client SET typecarte = 'bronze' WHERE idcli = 17;

-- Mise à jour client 2 - pas de remplacement, on récupère l'ancienne valeur (or)
UPDATE client SET typecarte = 'argile' WHERE idcli = 15;

-- Mise à jour client 3 - carte argent apparaît
UPDATE client SET typecarte = 'argent' WHERE idcli = 18;



-- Utilisation de la vue avec un tri décroissant sur le nombre de clients.
SELECT * FROM vue_nombre_clients ORDER BY nombre_de_clients DESC;
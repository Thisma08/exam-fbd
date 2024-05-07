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
    SELECT t.salaire_horaire_base, s.pourcentage 
    INTO tech_salaire_horaire, tech_pourcentage 
    FROM technicien t 
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
---Preparing the marketing anchor universe
DROP TABLE marketing_schema.customer_segmentation_base;

CREATE TABLE marketing_schema.customer_segmentation_base AS
(
    SELECT 
        CASE 
            WHEN b.customer_category LIKE '%HIGH_VALUE%' THEN 'High-Value Customer'
            WHEN b.customer_category LIKE '%MID_VALUE%' THEN 'Mid-Tier Customer'
            ELSE 'Low-Tier Customer'
        END AS customer_segment,
        a.customer_id AS anchor_id
    FROM
    (
        SELECT DISTINCT customer_id
        FROM marketing_schema.customer_affiliations
        WHERE affiliation_type = 'CUSTOMER_RELATIONSHIP' AND status = 'ACTIVE'
    ) a
    LEFT JOIN
    (
        SELECT *
        FROM marketing_schema.customer_profiles
        WHERE customer_category IN ('HIGH_VALUE', 'MID_VALUE', 'LOW_VALUE')
    ) b
    ON a.customer_id = b.customer_id
    GROUP BY 1, 2
    ORDER BY 1, 2
);

---Mapping Apex customers to Anchor customers
DROP TABLE marketing_schema.customer_apex_mapping;

CREATE TABLE marketing_schema.customer_apex_mapping AS
(
    SELECT anchor_id, 
           CASE WHEN apex_ct > 1 THEN 'NA' ELSE apex_id END AS final_apex_id
    FROM
    (
        SELECT c.*, COUNT(apex_id) OVER (PARTITION BY anchor_id) AS apex_ct
        FROM
        (
            SELECT anchor_id, b.customer_id AS apex_id
            FROM marketing_schema.customer_segmentation_base a
            LEFT JOIN
            (
                SELECT *
                FROM marketing_schema.customer_affiliations
                WHERE affiliation_type = 'APEX_CUSTOMER_RELATION' AND status = 'ACTIVE'
            ) b
            ON a.anchor_id = b.from_customer_id
        ) c
        ORDER BY apex_ct DESC
    ) d
    GROUP BY 1, 2
);

---Mapping customer locations and segmentation data
DROP TABLE marketing_schema.customer_location_segmentation;

CREATE TABLE marketing_schema.customer_location_segmentation AS
(
    SELECT e.*, 'Not Mapped' AS TERRITORY_ID, 'Not Mapped' AS TERRITORY_NAME
    FROM
    (
        SELECT a.*, d.territory_name AS NAS_TERRITORY_ID, d.description AS NAS_TERRITORY
        FROM marketing_schema.customer_apex_mapping a
        LEFT JOIN
        (
            SELECT b.*, CASE WHEN c.customer_id IS NOT NULL THEN c.customer_id ELSE network_id END AS customer_id
            FROM marketing_schema.customer_alignment b
            LEFT JOIN marketing_schema.customer_data_merge c
            ON b.network_id = c.legacy_customer_id
            WHERE team = 'NAS'
        ) d
        ON a.anchor_id = d.customer_id
    ) e
    LEFT JOIN
    (
        SELECT b.*, CASE WHEN c.customer_id IS NOT NULL THEN c.customer_id ELSE network_id END AS customer_id
        FROM marketing_schema.customer_alignment b
        LEFT JOIN marketing_schema.customer_data_merge c
        ON b.network_id = c.legacy_customer_id
        WHERE team = 'MDM'
    ) f
    ON e.anchor_id = f.customer_id
);

---Sales Performance Analysis: Tracking Shipments & Sales Impact
DROP TABLE marketing_schema.customer_sales_performance;

CREATE TABLE marketing_schema.customer_sales_performance AS
(
    SELECT c.*, d.shipment_date,
           d.year_month, d.year, sales_volume
    FROM marketing_schema.customer_location_segmentation c
    INNER JOIN
    (
        SELECT customer_id, product, shipment_date,
               TO_CHAR(shipment_date, 'YYYY-MM') AS year_month,
               TO_CHAR(shipment_date, 'YYYY') AS year,
               ROUND(SUM(quantity_sold)) AS sales_volume
        FROM marketing_schema.customer_shipments
        WHERE product IN ('PRODUCT_A', 'PRODUCT_B', 'PRODUCT_C')
        GROUP BY 1, 2, 3, 4, 5
    ) d
    ON c.anchor_id = d.customer_id
);

---Marketing Campaign Analysis: Call Outreach & Engagement
DROP TABLE marketing_schema.marketing_campaign_performance;

CREATE TABLE marketing_schema.marketing_campaign_performance AS
(
    SELECT e.*, CASE WHEN f.customer_id IS NOT NULL THEN 'Business' ELSE 'Individual' END AS customer_type
    FROM
    (
        SELECT c.*, d.product_name
        FROM
        (
            SELECT a.*, b.product_id
            FROM
            (
                SELECT *
                FROM marketing_schema.customer_call_logs
                WHERE campaign_id IN ('CAMP_001', 'CAMP_002')
            ) a
            LEFT JOIN marketing_schema.call_details b
            ON a.call_id = b.call_id
        ) c
        LEFT JOIN
        (
            SELECT *
            FROM marketing_schema.campaign_products
            WHERE product_name IN ('PRODUCT_A', 'PRODUCT_B')
        ) d
        ON c.product_id = d.product_id
    ) e
    LEFT JOIN marketing_schema.customer_profiles f
    ON e.customer_id = f.customer_id
    WHERE e.customer_id IS NOT NULL
);

---Aggregated Marketing Report
SELECT region, customer_segment, SUM(sales_volume) AS total_sales,
       COUNT(DISTINCT customer_id) AS engaged_customers,
       COUNT(DISTINCT call_id) AS total_calls,
       AVG(sales_volume) AS avg_sales_per_customer
FROM marketing_schema.marketing_campaign_performance a
JOIN marketing_schema.customer_sales_performance b
ON a.customer_id = b.customer_id
GROUP BY 1, 2
ORDER BY total_sales DESC;

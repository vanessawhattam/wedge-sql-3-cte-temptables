-- 3.1
-- From owner_spend_date, create temp table owner_year_month
-- include cols card_no, year, month, sum(spend), sum(items)
CREATE TEMP TABLE tmp_owner_year_month AS
	SELECT card_no, 
	strftime("%Y", date) AS "Year",
	strftime("%m", date) AS "Month",
	SUM(spend) AS "Spend",
	SUM(items) AS "Items"
FROM owner_spend_date
GROUP BY card_no, "Year", "Month";

-- 3.2
-- Use temp table, return year, month, total spend for 5 highest y-m combos
SELECT Year, Month, sum(Spend) as "Total Spend"
FROM tmp_owner_year_month
GROUP BY Year, Month
ORDER BY "Total Spend" DESC
LIMIT 5;

-- 3.3
-- Use temp table and owners table, return avg spend by month (across all yrs) for owners in zip 55405
-- use subquery to get correct card_no values, 
-- Order by month and round to 2 decimals
SELECT Month, tmp_owner_year_month.card_no, ROUND(AVG(Spend), 2) as "Avg Spend" 
FROM tmp_owner_year_month
WHERE tmp_owner_year_month.card_no in (SELECT card_no
									   FROM owners
									   WHERE zip = 55405)
GROUP BY tmp_owner_year_month.card_no, Month
ORDER BY Month;

-- 3.4 
-- Return zip code and total spend for top 3 zips by total spend
SELECT zip, sum(spend) as "Total Spend"
FROM owner_spend_date
INNER JOIN owners on owner_spend_date.card_no = owners.card_no
GROUP BY zip
ORDER BY "Total Spend" DESC
LIMIT 3;

-- 3.5 
-- Repeat 3.3 but include month and one col of avg sales for each zip in 3.4
-- start with 3.3, call the results avg_spend_55405
-- Join 2 more CTEs to make cols for the other two zips keep with avg_spend_XXXXX names
WITH avg_spend_55405 AS(
	SELECT Month, ROUND(AVG(Spend), 2) as "Avg Spend" 
	FROM tmp_owner_year_month
	WHERE card_no in (SELECT card_no
					  FROM owners
					  WHERE zip = 55405)
	GROUP BY Month
	ORDER BY Month), avg_spend_55408 AS(
	SELECT Month, ROUND(AVG(Spend), 2) as "Avg Spend" 
	FROM tmp_owner_year_month
	WHERE card_no in (SELECT card_no
					  FROM owners
					  WHERE zip = 55408)
	GROUP BY Month
	ORDER BY Month), avg_spend_55403 AS(
	SELECT Month, ROUND(AVG(Spend), 2) as "Avg Spend" 
	FROM tmp_owner_year_month
	WHERE card_no in (SELECT card_no
					  FROM owners
					  WHERE zip = 55403)
	GROUP BY Month
	ORDER BY Month)
SELECT tmp_owner_year_month.Month, 
avg_spend_55405."Avg Spend" AS "Avg Spend 55405", 
avg_spend_55408."Avg Spend" AS "Avg Spend 55408", 
avg_spend_55403."Avg Spend" AS "Avg Spend 55403"
FROM tmp_owner_year_month
INNER JOIN avg_spend_55405 on tmp_owner_year_month.Month = avg_spend_55405.Month
INNER JOIN avg_spend_55408 on tmp_owner_year_month.Month = avg_spend_55408.Month
INNER JOIN avg_spend_55403 on tmp_owner_year_month.Month = avg_spend_55403.Month
GROUP BY tmp_owner_year_month.Month
ORDER BY tmp_owner_year_month.Month;

-- 3.6
-- Rewrite 3.1 adding col called total_spend, which is total across years and months by owner
-- Use a CTE to calculate total_sales and JOIN to previous QUERY
-- Add a line at beginning to delete the temp table if it eists
DROP TABLE IF EXISTS tmp_owner_year_month;
CREATE TEMP TABLE tmp_owner_year_month AS
SELECT owner_spend_date.card_no, 
       strftime("%Y", owner_spend_date.date) AS "year",
       strftime("%m", owner_spend_date.date) AS "month",
       SUM(owner_spend_date.spend) AS "spend",
       SUM(owner_spend_date.items) AS "items",
       tsp.total_spend
FROM owner_spend_date 
JOIN (
    SELECT card_no, SUM(spend) AS "total_spend"
    FROM owner_spend_date
    GROUP BY card_no
) tsp ON owner_spend_date.card_no = tsp.card_no
GROUP BY owner_spend_date.card_no, "year", "month";

-- Run this after rebuilding your temporary table.
SELECT COUNT(DISTINCT(card_no)) AS owners,
COUNT(DISTINCT(year)) AS years,
COUNT(DISTINCT(month)) AS months,
ROUND(AVG(spend),2) AS avg_spend,
ROUND(AVG(items),1) AS avg_items,
ROUND(SUM(spend)/SUM(items),2) AS avg_item_price
FROM tmp_owner_year_month;

-- 3.7
-- Create "owner at a glance" VIEW from owner_spend_date call it vw_owner_recent
-- total amt by owner, avg spend per trans, # dates they shopped, # trans they have, date most recent visit
--DROP VIEW if EXISTS vw_owner_recent;
CREATE VIEW vw_owner_recent AS 
	SELECT card_no, sum(spend) as "total_spend", sum(spend)/sum(trans) as "trans_avg_spend",
			count(date) as "num_shopping_days", sum(trans) as "num_trans", MAX(date) as "most_recent_shop"
	FROM owner_spend_date
	GROUP BY card_no;
	
-- Run this after creating the view
SELECT COUNT(DISTINCT card_no) AS owners,
ROUND(SUM(total_spend)/1000,1) AS spend_k
FROM vw_owner_recent
WHERE 5 < num_trans AND
num_trans < 25 AND
SUBSTR(most_recent_shop,1,4) IN ('2016','2017');

-- 3.8 
-- create new table called owner_recent, built off of vw_owner_recent, add col "last_spend"
-- last_spend is amy spent on date of last visit
-- will be joining owner_spend_date to itself, but using view as intermediary
--DROP TABLE if EXISTS owner_recent;
CREATE TABLE owner_recent AS
SELECT
    vw_owner_recent.card_no,
    vw_owner_recent.total_spend,
    vw_owner_recent.trans_avg_spend,
    vw_owner_recent.num_shopping_days,
    vw_owner_recent.num_trans,
    vw_owner_recent.most_recent_shop,
    osd.spend AS last_spend
FROM vw_owner_recent 
JOIN owner_spend_date osd ON vw_owner_recent.card_no = osd.card_no 
	AND vw_owner_recent.most_recent_shop = osd.date;

-- Select a row from the table
SELECT *
FROM owner_recent
WHERE card_no = "18736";

-- Select a row from the view
SELECT *
FROM vw_owner_recent
WHERE card_no = "18736";

/*  1. The time difference between the two queries was approximately 1900ms, with the 
	table running more quickly than the view.
	2. The time difference exists because the table is static, while the view must be 
	re-run on the original table each time it is run. This provides the most up-to-date
	information, but means that the query is going to be slow. */
	
-- 3.9
-- Identify high-value owners who have lapsed
-- Return cols from owner_recent that meet criteria
-- last spend < 1/2 avg spend, total spend >= 5000, 270+ shopping dates, 
-- last visit >60 days before 2017-01-31, last spend > $10
-- ORDER BY drop in spend DESC, and total_spend
SELECT *
FROM owner_recent 
WHERE last_spend < 0.5*trans_avg_spend
	AND total_spend > 5000
	AND num_shopping_days >= 270
	AND most_recent_shop <= DATE('2017-01-31', '-60 days')
	AND last_spend > 10
ORDER BY (trans_avg_spend - last_spend), total_spend DESC;

-- 3.10
-- zip code filtering - find those people with 'other' zip codes
-- return cols for owners with following criteria
-- non-null, non-blank, other zip code,
-- last spend < 1/2 avg spend, total spend >= 5000, 100+ shopping dates, 
-- last visit >60 days before 2017-01-31, last spend > $10
-- Include zip code in results (join from owners table)
-- ORDER BY drop in spend DESC, and total_spend
SELECT owner_recent.card_no, 
	   zip,
	   total_spend,
	   trans_avg_spend,
	   num_shopping_days,
	   num_trans,
	   most_recent_shop,
	   last_spend
FROM owner_recent 
INNER JOIN owners ON owner_recent.card_no = owners.card_no
WHERE zip NOT IN (55405, 55442, 55416, 55408, 55404, 55403)
	AND zip NOT NULL
	AND last_spend < 0.5*trans_avg_spend
	AND total_spend > 5000
	AND num_shopping_days >= 100
	AND most_recent_shop <= DATE('2017-01-31', '-60 days')
	AND last_spend > 10
ORDER BY (trans_avg_spend - last_spend), total_spend DESC;








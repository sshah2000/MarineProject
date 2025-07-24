--All of the data
select * from positions p 

--The number of collected data
select COUNT(*) from positions p 

--Returns the 50 most recent ship positions by timestamp newest first
SELECT * 
FROM positions 
ORDER BY ts_utc DESC 
LIMIT 50;

--Same as above but for 5
SELECT *
FROM positions
ORDER BY ts_utc DESC
LIMIT 5;

--Data Latency check 
SELECT
  datetime('now')            AS now_utc,
  MAX(ts_utc)                AS newest_row,
  ROUND( (julianday('now') - julianday(MAX(ts_utc))) * 24*60, 2 ) AS lag_min
FROM positions;

--Shows the top 10 updated to the database
SELECT *
FROM positions
ORDER BY ts_utc DESC
LIMIT 10;

--Ships that updates most frequently
SELECT v.shipname, p.ship_id, COUNT(*) AS updates, MAX(ts_utc) AS last_seen
FROM positions p
JOIN vessels v ON p.ship_id = v.ship_id
GROUP BY p.ship_id
ORDER BY updates DESC
LIMIT 10;


--Latest positions to plot on a map in Excel 
SELECT v.shipname, p.ship_id, p.lat, p.lon, p.ts_utc
FROM positions p
JOIN vessels v ON p.ship_id = v.ship_id
WHERE (p.ship_id, p.ts_utc) IN (
  SELECT ship_id, MAX(ts_utc)
  FROM positions
  GROUP BY ship_id
);


--Ships that have not updated in 5+ minutes
SELECT shipname, ship_id, MAX(ts_utc) AS last_seen
FROM positions
JOIN vessels USING(ship_id)
GROUP BY ship_id
HAVING STRFTIME('%s', 'now') - STRFTIME('%s', last_seen) > 300
ORDER BY last_seen ASC;


--Ships would fly a certain flag
SELECT shipname, flag, lat, lon, ts_utc
FROM positions
JOIN vessels USING(ship_id)
WHERE flag = 'US'
ORDER BY ts_utc DESC
LIMIT 20;

--Provides the destination
SELECT shipname, destination, MAX(ts_utc) AS last_seen
FROM positions
JOIN vessels USING(ship_id)
WHERE destination IS NOT NULL AND destination != ''
GROUP BY ship_id
ORDER BY last_seen DESC
LIMIT 20;


--Common Destinations
SELECT destination, COUNT(*) AS count
FROM positions
WHERE destination IS NOT NULL AND destination != ''
GROUP BY destination
ORDER BY count DESC
LIMIT 20;



SELECT game_id,
       time_bucket(INTERVAL '1 hour', created_at) AS bucket,
       AVG(score),
       MAX(score),
       MIN(score)
FROM plays
GROUP BY game_id, bucket;

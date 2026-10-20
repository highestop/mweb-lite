-- Add only the Timeline scenario to a fresh, materialized Library fixture.
INSERT INTO cat (uuid, name, pid, sort) VALUES (106, 'Timeline', 0, 3);
INSERT INTO article (uuid, state, dateAdd, dateModif, dateArt) VALUES
    (11000, 1, CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER)),
    (11001, 1, CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-09-18T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER)),
    (11002, 1, CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-08-17T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER)),
    (11003, 1, CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-07-16T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER)),
    (11004, 1, CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-06-15T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER)),
    (11006, 1, CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-05-14T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-01-02T04:00:00Z') AS INTEGER));
INSERT INTO cat_article VALUES (106, 11000), (106, 11001), (106, 11002), (106, 11003), (106, 11004), (106, 11006);

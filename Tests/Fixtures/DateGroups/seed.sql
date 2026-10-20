-- Local dates below use Asia/Shanghai. Some same-day notes cross a UTC date boundary.
INSERT INTO cat (uuid, name, pid, sort) VALUES (107, 'Date Groups', 0, 3);
INSERT INTO article (uuid, state, dateAdd, dateModif, dateArt) VALUES
    (12001, 1, CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER)),
    (12002, 1, CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-18T23:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER)),
    (12003, 1, CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-18T16:30:00Z') AS INTEGER), CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER)),
    (12004, 1, CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-18T12:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER)),
    (12005, 1, CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-09-21T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER)),
    (12006, 1, CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-17T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-01-02T04:00:00Z') AS INTEGER));
INSERT INTO cat_article VALUES (107, 12001), (107, 12002), (107, 12003), (107, 12004), (107, 12005), (107, 12006);

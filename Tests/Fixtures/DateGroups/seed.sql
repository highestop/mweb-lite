-- Creation dates use Asia/Shanghai; same-day notes cross a UTC boundary.
-- Modification dates deliberately differ and must not determine display order or headings.
INSERT INTO cat (uuid, name, pid, sort) VALUES (107, 'Date Groups', 0, 3);
INSERT INTO article (uuid, state, dateAdd, dateModif, dateArt) VALUES
    (12001, 1, CAST(strftime('%s', '2026-10-19T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T04:00:00Z') AS INTEGER)),
    (12002, 1, CAST(strftime('%s', '2026-10-18T23:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-18T23:00:00Z') AS INTEGER)),
    (12003, 1, CAST(strftime('%s', '2026-10-18T16:30:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-18T16:30:00Z') AS INTEGER)),
    (12004, 1, CAST(strftime('%s', '2026-10-18T12:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-18T12:00:00Z') AS INTEGER)),
    (12005, 1, CAST(strftime('%s', '2026-09-21T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-09-21T04:00:00Z') AS INTEGER)),
    (12006, 1, CAST(strftime('%s', '2025-10-17T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-20T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-17T04:00:00Z') AS INTEGER));
INSERT INTO cat_article VALUES (107, 12001), (107, 12002), (107, 12003), (107, 12004), (107, 12005), (107, 12006);

-- Keep enough rows after each later boundary to exercise pinned headers by scrolling.
INSERT INTO article (uuid, state, dateAdd, dateModif, dateArt) VALUES
    (12007, 1, CAST(strftime('%s', '2026-09-20T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-09-20T04:00:00Z') AS INTEGER)),
    (12008, 1, CAST(strftime('%s', '2026-09-20T03:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-09-20T03:00:00Z') AS INTEGER)),
    (12009, 1, CAST(strftime('%s', '2026-09-20T02:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-09-20T02:00:00Z') AS INTEGER)),
    (12010, 1, CAST(strftime('%s', '2026-09-20T01:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-09-20T01:00:00Z') AS INTEGER)),
    (12011, 1, CAST(strftime('%s', '2025-10-16T09:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T09:00:00Z') AS INTEGER)),
    (12012, 1, CAST(strftime('%s', '2025-10-16T08:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T08:00:00Z') AS INTEGER)),
    (12013, 1, CAST(strftime('%s', '2025-10-16T07:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T07:00:00Z') AS INTEGER)),
    (12014, 1, CAST(strftime('%s', '2025-10-16T06:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T06:00:00Z') AS INTEGER)),
    (12015, 1, CAST(strftime('%s', '2025-10-16T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T05:00:00Z') AS INTEGER)),
    (12016, 1, CAST(strftime('%s', '2025-10-16T04:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T04:00:00Z') AS INTEGER)),
    (12017, 1, CAST(strftime('%s', '2025-10-16T03:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T03:00:00Z') AS INTEGER)),
    (12018, 1, CAST(strftime('%s', '2025-10-16T02:00:00Z') AS INTEGER), CAST(strftime('%s', '2026-10-19T05:00:00Z') AS INTEGER), CAST(strftime('%s', '2025-10-16T02:00:00Z') AS INTEGER));
INSERT INTO cat_article VALUES (107, 12007), (107, 12008), (107, 12009), (107, 12010), (107, 12011), (107, 12012), (107, 12013), (107, 12014), (107, 12015), (107, 12016), (107, 12017), (107, 12018);

-- Older pinned/custom-sort metadata must remain stored without changing display order.
UPDATE article SET isTop = 1, sort = 999 WHERE uuid = 12006;

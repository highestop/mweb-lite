#!/usr/bin/env python3
"""Create synthetic MWeb data for development. Never reads an existing library."""
import base64
import pathlib
import sqlite3
import sys
import time

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'build/Demo Library').resolve()
if root.exists():
    raise SystemExit(f'Refusing to overwrite an existing directory: {root}')
(root / 'docs/media/17924000000001').mkdir(parents=True)
connection = sqlite3.connect(root / 'mainlib.db')
connection.executescript('''
CREATE TABLE article (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, state INTEGER DEFAULT 1, type INTEGER DEFAULT 0, docName TEXT, dateAdd INTEGER, dateModif INTEGER, dateArt INTEGER, sort INTEGER DEFAULT 0, isTop INTEGER DEFAULT 0, customField TEXT);
CREATE TABLE cat (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, name TEXT, pid INTEGER DEFAULT 0, sort INTEGER DEFAULT 0, sortType INTEGER DEFAULT 0, catType INTEGER DEFAULT 0);
CREATE TABLE cat_article (rid INTEGER, aid INTEGER);
CREATE TABLE tag (id INTEGER PRIMARY KEY, uuid INTEGER, name TEXT);
CREATE TABLE tag_article (rid INTEGER, aid INTEGER);
CREATE TABLE settings (id INTEGER PRIMARY KEY, key TEXT, value TEXT);
''')
categories = [(101, '写作空间', 0, 0), (102, '产品与设计', 101, 0), (103, '日常随记', 101, 1), (104, '技术笔记', 0, 1)]
connection.executemany('INSERT INTO cat(uuid,name,pid,sort) VALUES(?,?,?,?)', categories)
documents = [
('17924000000001', 102, '''# 让写作回到内容本身

一个轻量的本地空间，保存灵感，也容纳长篇思考。

[TOC]

## 从熟悉的文库开始

MWeb Lite 直接读取原有的 **分类结构** 与 Markdown 文件。你可以在左侧选择分类，在这里安静地写作。

> 好的工具退到内容之后，让思路自然发生。

## 今天的计划

- [x] 整理写作空间
- [x] 连接本地文库
- [ ] 写下新的想法

## 三种阅读方式

| 模式 | 快捷键 | 适合 |
| --- | --- | --- |
| 编辑 / 预览 | ⌘R | 专注写作与阅读 |
| 边编辑边预览 | ⌘4 | 即时检查排版 |

## 一点代码

```swift
let ideas = ["记录", "整理", "创造"]
for idea in ideas {
    print(idea)
}
```

也支持公式：$E = mc^2$。[^note]

![本地图片 -w96](media/17924000000001/sample.png)

[阅读下一篇](mweblib://17924000000002)

[^note]: 这是用于验证脚注显示的示例文本。
'''),
('17924000000002', 102, '# 设计中的留白\n\n留白让层次更清晰，也让注意力有地方停留。\n\n## 三个原则\n\n1. 每一处信息都应有明确的作用\n2. 让阅读顺序自然发生\n3. 保持节奏与一致性\n'),
('17924000000003', 103, '# 秋日随记\n\n今天的风很轻，适合走一段没有目的的路。\n\n- 咖啡店的一页书\n- 路边的一棵树\n- 留给明天的一句话\n'),
('17924000000004', 104, '# Markdown 语法速查\n\n**粗体**、*斜体*、~~删除线~~ 与 `行内代码`。\n\n```mermaid\ngraph LR\n    A[灵感] --> B[写作]\n    B --> C[整理]\n```\n\n$$\n\\int_0^1 x^2 dx = \\frac{1}{3}\n$$\n'),
('17924000000005', None, '# 待整理的灵感\n\n把尚未归类的想法先放在这里。\n')]
now = int(time.time())
for offset, (uuid, category, content) in enumerate(documents):
    connection.execute('INSERT INTO article(uuid,dateAdd,dateModif,dateArt,customField) VALUES(?,?,?,?,?)', (int(uuid), now-offset*86400, now-offset*86400, now, 'preserve me'))
    if category:
        connection.execute('INSERT INTO cat_article VALUES(?,?)', (category, int(uuid)))
    (root / 'docs' / f'{uuid}.md').write_text(content, encoding='utf-8')
connection.commit()
connection.close()
(root / 'docs/media/17924000000001/sample.png').write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1cAAAAASUVORK5CYII='))
print(root)

# Kitchen Rat — textures-v2: полный список для скачивания

Все текстуры CC0 (бесплатно, можно в коммерческую игру). По каждой позиции:
ссылка → какое разрешение качать → какие файлы взять → во что переименовать.

**Правило переименования (везде одинаково):**
- файл цвета (`..._Color.jpg` на ambientCG, `..._diff_...jpg` на Poly Haven) → `<имя>.jpg`
- файл нормалей (`..._NormalGL.jpg` / `..._nor_gl_...jpg`) → `<имя>_normal.jpg`
- файл шероховатости (`..._Roughness.jpg` / `..._rough_...jpg`) → `<имя>_rough.jpg` — необязательный, но раз архив уже скачан, бери и его.

В итоговый пак кладутся ТОЛЬКО переименованные JPG, все в корень архива
`textures.zip` (без папок). Релиз — с тегом ровно `textures-v2`.
Адрес в cdn.json и обновление загрузки — правки Muse в ветке.

---

## Материалы мебели и поверхностей

| # | Имя в паке | Откуда | Разр. | Что это |
|---|---|---|---|---|
| 1 | `wood` | [Wood075 — ambientCG](https://ambientcg.com/view?id=Wood075) | 1K-JPG | Тёплое средне-коричневое дерево мебели (#583f2d) |
| 2 | `wood_dark` | [Wood006 — ambientCG](https://ambientcg.com/view?id=Wood006) | 1K-JPG | Тёмное дерево, орех (#4e3e32) |
| 3 | `fabric` | [Fabric081C — ambientCG](https://ambientcg.com/a/Fabric081C) | 1K-JPG | Ткань диванов/кресел — та же, что в v1, светлая нейтральная |
| 4 | `leather` | [Leather026 — ambientCG](https://ambientcg.com/view?id=Leather026) | 1K-JPG | Коричневая кожа, мелкое зерно |
| 5 | `ceramic_tile` | [Tiles028 — ambientCG](https://ambientcg.com/view?id=Tiles028) | **2K-JPG** | Плитка полов кухни/ванной, тёплая бежевая (#f0d6c0). ЗАМЕНА Tiles141 из v1 |
| 6 | `metal_matte` | [Metal010 — ambientCG](https://ambientcg.com/view?id=Metal010) | 1K-JPG | Матовая шлифованная сталь: холодильник, техника |
| 7 | `cardboard` | [Cardboard001 — ambientCG](https://ambientcg.com/a/Cardboard001) | 1K-JPG | Картон коробок (чуть потёртый — коробкам идёт) |
| 8 | `plastic` | [Plastic003 — ambientCG](https://ambientcg.com/view?id=Plastic003) | 1K-JPG | Почти ровный пластик: стиралка, сушилка, корзины |
| 9 | `counter_stone` | [Granite001A — ambientCG](https://ambientcg.com/view?id=Granite001A) | **2K-JPG** | Гранит столешниц. Глянь рядом Granite001B — бери тот, что теплее по превью |
| 10 | `tablecloth` | [Rough Linen — Poly Haven](https://polyhaven.com/a/rough_linen) | 1K | Льняное плетение скатертей. На Poly Haven файлы качаются по одному: Diffuse, Normal (GL), Rough |
| 11 | `crinkle` | [Foil001 — ambientCG](https://ambientcg.com/view?id=Foil001) | 1K-JPG | Мятая фольга |

Альтернатива столешнице, если захочешь мрамор вместо гранита:
[Marble 01 — Poly Haven](https://polyhaven.com/a/marble_01), 2K, файлы те же
(Diffuse / Normal GL / Rough) → переименовать в `counter_stone.*`.

## Полы

| # | Имя в паке | Откуда | Разр. | Что это |
|---|---|---|---|---|
| 12 | `floor_wood` | [WoodFloor064 — ambientCG](https://ambientcg.com/a/WoodFloor064) | **2K-JPG** | Широкие потёртые доски — тот же, что в v1 |
| 13 | `floor_concrete` | [Concrete034 — ambientCG](https://ambientcg.com/view?id=Concrete034) | **2K-JPG** | Бетон кладовой/подвала/прачечной |
| 14 | `carpet` | [Carpet014 — ambientCG](https://ambientcg.com/view?id=Carpet014) | **2K-JPG** | Ковёр с узором для жилых комнат. ВНИМАНИЕ: перед скачиванием посмотри превью — если расцветка холодная/синяя, скажи Muse, подберём другой |

Полы `floor_wood`, `floor_concrete` и `carpet` игра пока не умеет брать из
пака — Muse добавит слоты кодом (раунд 16). Файлы просто положи в пак.

## Стены

| # | Имя в паке | Откуда | Разр. | Что это |
|---|---|---|---|---|
| 15 | `wallpaper_damask` | [Wallpaper001A — ambientCG](https://ambientcg.com/view?id=Wallpaper001A) | **2K-JPG** | Дамаск-орнамент, самый светлый из трёх вариантов (B и C — тот же узор, другие цвета) |
| 16 | `wallpaper_brick` | [Whitewashed Brick — Poly Haven](https://polyhaven.com/a/whitewashed_brick) | 1K | Белёный кирпич кладовой/подвала, тёплый белый, местами проглядывает красный кирпич. Файлы: Diffuse / Normal (GL) / Rough |

## Качать НЕ надо (остаются процедурными)

- `wallpaper_stripes` — полосат
...[truncated 737 chars]
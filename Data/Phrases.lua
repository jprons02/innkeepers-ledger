-- Phrase templates, conjunctions and words, each with a stable numeric ID. Plain data, no
-- WoW API. Shape, ID ranges, record rules and content rules: docs/specs/phrase.md.
--
-- DRAFT: the wording is the maintainer's decision (docs/specs/phrase.md, section 9 and its
-- open questions). Before the first public release it can change freely. From then on an
-- ID is never reused and its meaning never changes; new phrases get new IDs.
--
-- One ID space, keyed directly by number (SyncProtocol looks every ID up here):
--   templates 1..499 (slotted from 1, slotless from 101), conjunctions 500..599,
--   words 1000..9999 in blocks of 100 per category (category k: 900 + 100k ..).
-- A template has a slot if its text holds "{w}"; any word fits any slot.
local _, ns = ...

ns.Data = ns.Data or {}

-- UI labels only, index = category number. They never appear in an entry.
ns.Data.PhraseCategories = {
  "Hearth and home",
  "Food and drink",
  "Company",
  "The road",
  "Places",
  "Sky and seasons",
  "Adventure",
  "Of the heart",
}

ns.Data.Phrases = {
  -- Templates with a slot.
  [1] = { kind = "template", text = "Rested here, dreaming of {w}." },
  [2] = { kind = "template", text = "Lingered a day longer for {w}." },
  [3] = { kind = "template", text = "Here's to {w}!" },
  [4] = { kind = "template", text = "Grateful for {w}." },
  [5] = { kind = "template", text = "Found {w} here." },
  [6] = { kind = "template", text = "Warmed by {w}." },
  [7] = { kind = "template", text = "Remember {w}." },
  [8] = { kind = "template", text = "Seek {w}, traveler." },
  [9] = { kind = "template", text = "Never forget {w}." },
  [10] = { kind = "template", text = "Tomorrow, {w}." },
  [11] = { kind = "template", text = "Will miss {w}." },
  [12] = { kind = "template", text = "Raised a cup to {w}." },
  [13] = { kind = "template", text = "The road led me to {w}." },
  [14] = { kind = "template", text = "Stopped to rest, thought of {w}." },
  [15] = { kind = "template", text = "Heard songs of {w}." },
  [16] = { kind = "template", text = "Traded tales of {w}." },
  [17] = { kind = "template", text = "Write home about {w}." },
  [18] = { kind = "template", text = "May you find {w}." },

  -- Templates without a slot.
  [101] = { kind = "template", text = "Rest well, traveler." },
  [102] = { kind = "template", text = "Slept like a stone." },
  [103] = { kind = "template", text = "Safe travels, friend." },
  [104] = { kind = "template", text = "Passed through here." },
  [105] = { kind = "template", text = "I will be back." },
  [106] = { kind = "template", text = "The fire was warm." },

  -- Conjunctions.
  [501] = { kind = "conj", text = "And then..." },
  [502] = { kind = "conj", text = "But..." },
  [503] = { kind = "conj", text = "Even so..." },
  [504] = { kind = "conj", text = "Best of all..." },

  -- Words, category 1: Hearth and home.
  [1001] = { kind = "word", cat = 1, text = "home" },
  [1002] = { kind = "word", cat = 1, text = "the hearth" },
  [1003] = { kind = "word", cat = 1, text = "a warm fire" },
  [1004] = { kind = "word", cat = 1, text = "a cozy corner" },
  [1005] = { kind = "word", cat = 1, text = "the common room" },
  [1006] = { kind = "word", cat = 1, text = "a good night's sleep" },
  [1007] = { kind = "word", cat = 1, text = "a warm blanket" },
  [1008] = { kind = "word", cat = 1, text = "a lantern's glow" },
  [1009] = { kind = "word", cat = 1, text = "a rocking chair" },
  [1010] = { kind = "word", cat = 1, text = "a window seat" },
  [1011] = { kind = "word", cat = 1, text = "the creaky stairs" },
  [1012] = { kind = "word", cat = 1, text = "a roof overhead" },
  [1013] = { kind = "word", cat = 1, text = "the inn's cat" },
  [1014] = { kind = "word", cat = 1, text = "the stables" },
  [1015] = { kind = "word", cat = 1, text = "a quiet room" },

  -- Words, category 2: Food and drink.
  [1101] = { kind = "word", cat = 2, text = "fresh bread" },
  [1102] = { kind = "word", cat = 2, text = "hot stew" },
  [1103] = { kind = "word", cat = 2, text = "a bowl of soup" },
  [1104] = { kind = "word", cat = 2, text = "sweet rolls" },
  [1105] = { kind = "word", cat = 2, text = "honey cakes" },
  [1106] = { kind = "word", cat = 2, text = "apple pie" },
  [1107] = { kind = "word", cat = 2, text = "a wheel of cheese" },
  [1108] = { kind = "word", cat = 2, text = "roast boar" },
  [1109] = { kind = "word", cat = 2, text = "fresh berries" },
  [1110] = { kind = "word", cat = 2, text = "a hearty breakfast" },
  [1111] = { kind = "word", cat = 2, text = "a second helping" },
  [1112] = { kind = "word", cat = 2, text = "hot tea" },
  [1113] = { kind = "word", cat = 2, text = "warm porridge" },
  [1114] = { kind = "word", cat = 2, text = "spiced cider" },
  [1115] = { kind = "word", cat = 2, text = "a mug of ale" },

  -- Words, category 3: Company.
  [1201] = { kind = "word", cat = 3, text = "old friends" },
  [1202] = { kind = "word", cat = 3, text = "new friends" },
  [1203] = { kind = "word", cat = 3, text = "good company" },
  [1204] = { kind = "word", cat = 3, text = "fellow travelers" },
  [1205] = { kind = "word", cat = 3, text = "my companions" },
  [1206] = { kind = "word", cat = 3, text = "the guild" },
  [1207] = { kind = "word", cat = 3, text = "the whole party" },
  [1208] = { kind = "word", cat = 3, text = "a warm welcome" },
  [1209] = { kind = "word", cat = 3, text = "a kind word" },
  [1210] = { kind = "word", cat = 3, text = "a good deed" },
  [1211] = { kind = "word", cat = 3, text = "a shared meal" },
  [1212] = { kind = "word", cat = 3, text = "a good laugh" },
  [1213] = { kind = "word", cat = 3, text = "tall tales" },
  [1214] = { kind = "word", cat = 3, text = "a song by the fire" },
  [1215] = { kind = "word", cat = 3, text = "a game of cards" },

  -- Words, category 4: The road.
  [1301] = { kind = "word", cat = 4, text = "the long road" },
  [1302] = { kind = "word", cat = 4, text = "the open road" },
  [1303] = { kind = "word", cat = 4, text = "a winding path" },
  [1304] = { kind = "word", cat = 4, text = "the next town" },
  [1305] = { kind = "word", cat = 4, text = "the mountain pass" },
  [1306] = { kind = "word", cat = 4, text = "a river crossing" },
  [1307] = { kind = "word", cat = 4, text = "the ferry" },
  [1308] = { kind = "word", cat = 4, text = "a shortcut" },
  [1309] = { kind = "word", cat = 4, text = "a well-worn map" },
  [1310] = { kind = "word", cat = 4, text = "a trusty compass" },
  [1311] = { kind = "word", cat = 4, text = "a signpost" },
  [1312] = { kind = "word", cat = 4, text = "a quiet trail" },
  [1313] = { kind = "word", cat = 4, text = "the crossroads" },
  [1314] = { kind = "word", cat = 4, text = "the way home" },
  [1315] = { kind = "word", cat = 4, text = "faraway lands" },

  -- Words, category 5: Places.
  [1401] = { kind = "word", cat = 5, text = "the sea" },
  [1402] = { kind = "word", cat = 5, text = "the mountains" },
  [1403] = { kind = "word", cat = 5, text = "the deep forest" },
  [1404] = { kind = "word", cat = 5, text = "a quiet village" },
  [1405] = { kind = "word", cat = 5, text = "the big city" },
  [1406] = { kind = "word", cat = 5, text = "the harbor" },
  [1407] = { kind = "word", cat = 5, text = "rolling hills" },
  [1408] = { kind = "word", cat = 5, text = "a still lake" },
  [1409] = { kind = "word", cat = 5, text = "a waterfall" },
  [1410] = { kind = "word", cat = 5, text = "the meadow" },
  [1411] = { kind = "word", cat = 5, text = "the old bridge" },
  [1412] = { kind = "word", cat = 5, text = "the countryside" },
  [1413] = { kind = "word", cat = 5, text = "a hidden valley" },
  [1414] = { kind = "word", cat = 5, text = "the coast" },
  [1415] = { kind = "word", cat = 5, text = "the snowy peaks" },

  -- Words, category 6: Sky and seasons.
  [1501] = { kind = "word", cat = 6, text = "the morning sun" },
  [1502] = { kind = "word", cat = 6, text = "a starry night" },
  [1503] = { kind = "word", cat = 6, text = "the full moon" },
  [1504] = { kind = "word", cat = 6, text = "soft rain" },
  [1505] = { kind = "word", cat = 6, text = "fresh snow" },
  [1506] = { kind = "word", cat = 6, text = "a summer breeze" },
  [1507] = { kind = "word", cat = 6, text = "autumn leaves" },
  [1508] = { kind = "word", cat = 6, text = "the first frost" },
  [1509] = { kind = "word", cat = 6, text = "a thunderstorm" },
  [1510] = { kind = "word", cat = 6, text = "morning mist" },
  [1511] = { kind = "word", cat = 6, text = "a rainbow" },
  [1512] = { kind = "word", cat = 6, text = "the sunset" },
  [1513] = { kind = "word", cat = 6, text = "the dawn" },
  [1514] = { kind = "word", cat = 6, text = "the harvest" },
  [1515] = { kind = "word", cat = 6, text = "spring flowers" },

  -- Words, category 7: Adventure.
  [1601] = { kind = "word", cat = 7, text = "adventure" },
  [1602] = { kind = "word", cat = 7, text = "treasure" },
  [1603] = { kind = "word", cat = 7, text = "a new quest" },
  [1604] = { kind = "word", cat = 7, text = "an old legend" },
  [1605] = { kind = "word", cat = 7, text = "a lucky find" },
  [1606] = { kind = "word", cat = 7, text = "a hidden cave" },
  [1607] = { kind = "word", cat = 7, text = "ancient ruins" },
  [1608] = { kind = "word", cat = 7, text = "a secret door" },
  [1609] = { kind = "word", cat = 7, text = "a sunken ship" },
  [1610] = { kind = "word", cat = 7, text = "a glinting gem" },
  [1611] = { kind = "word", cat = 7, text = "a dragon" },
  [1612] = { kind = "word", cat = 7, text = "the wolves" },
  [1613] = { kind = "word", cat = 7, text = "the murlocs" },
  [1614] = { kind = "word", cat = 7, text = "a long climb" },
  [1615] = { kind = "word", cat = 7, text = "the unknown" },

  -- Words, category 8: Of the heart.
  [1701] = { kind = "word", cat = 8, text = "rest" },
  [1702] = { kind = "word", cat = 8, text = "peace and quiet" },
  [1703] = { kind = "word", cat = 8, text = "a fresh start" },
  [1704] = { kind = "word", cat = 8, text = "good fortune" },
  [1705] = { kind = "word", cat = 8, text = "hope" },
  [1706] = { kind = "word", cat = 8, text = "courage" },
  [1707] = { kind = "word", cat = 8, text = "sweet dreams" },
  [1708] = { kind = "word", cat = 8, text = "a clear mind" },
  [1709] = { kind = "word", cat = 8, text = "wonder" },
  [1710] = { kind = "word", cat = 8, text = "patience" },
  [1711] = { kind = "word", cat = 8, text = "a second chance" },
  [1712] = { kind = "word", cat = 8, text = "simple joys" },
  [1713] = { kind = "word", cat = 8, text = "a long nap" },
  [1714] = { kind = "word", cat = 8, text = "old memories" },
  [1715] = { kind = "word", cat = 8, text = "the little things" },
}

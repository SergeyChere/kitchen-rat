using System.Collections.Generic;
using UnityEngine;

namespace KitchenRat
{
    /// <summary>
    /// A* on a 20 cm grid over the room, like the prototype: cells under furniture legs, walls and hiding spots
    /// (under tables, chairs, sofas) are blocked, so the cat and the owner walk around them and can't reach a hidden rat.
    /// </summary>
    public class NavGrid
    {
        public const float Cell = 0.2f;
        public readonly int gw, gh;
        readonly bool[] blocked;
        readonly Vector3 origin; // world position of the north-west corner

        public NavGrid(IEnumerable<Zone> noGo, float inflate = 0.07f)
        {
            gw = Mathf.RoundToInt(Nights.RoomW / 100f / Cell);
            gh = Mathf.RoundToInt(Nights.RoomD / 100f / Cell);
            origin = Nights.World(0, 0);
            blocked = new bool[gw * gh];
            var zones = new List<Zone>(noGo);
            var half = new Vector3(Cell / 2f + inflate, 0.18f, Cell / 2f + inflate);
            for (int y = 0; y < gh; y++)
                for (int x = 0; x < gw; x++)
                {
                    Vector3 c = CellCenter(x, y);
                    bool b = x == 0 || y == 0 || x == gw - 1 || y == gh - 1;
                    if (!b) b = Physics.CheckBox(c + Vector3.up * 0.24f, half, Quaternion.identity, RatController.Mask, QueryTriggerInteraction.Ignore);
                    if (!b) foreach (var z in zones) if (z.ContainsXZ(c, inflate + 0.05f)) { b = true; break; }
                    blocked[y * gw + x] = b;
                }
        }

        public Vector3 CellCenter(int x, int y) => origin + new Vector3((x + 0.5f) * Cell, 0f, -(y + 0.5f) * Cell);

        public Vector2Int ToCell(Vector3 p) => new Vector2Int(
            Mathf.Clamp(Mathf.FloorToInt((p.x - origin.x) / Cell), 0, gw - 1),
            Mathf.Clamp(Mathf.FloorToInt((origin.z - p.z) / Cell), 0, gh - 1));

        public bool Blocked(int x, int y) => x < 0 || y < 0 || x >= gw || y >= gh || blocked[y * gw + x];
        public bool BlockedAt(Vector3 p) { var c = ToCell(p); return Blocked(c.x, c.y); }

        public Vector2Int NearestFree(Vector2Int c)
        {
            if (!Blocked(c.x, c.y)) return c;
            for (int r = 1; r < 12; r++)
                for (int dy = -r; dy <= r; dy++)
                    for (int dx = -r; dx <= r; dx++)
                        if ((Mathf.Abs(dx) == r || Mathf.Abs(dy) == r) && !Blocked(c.x + dx, c.y + dy)) return new Vector2Int(c.x + dx, c.y + dy);
            return c;
        }

        public Vector3 FreePoint(Vector3 p) { var c = NearestFree(ToCell(p)); return CellCenter(c.x, c.y); }

        public bool LineClear(Vector3 a, Vector3 b)
        {
            float d = Vector3.Distance(a, b);
            int n = Mathf.CeilToInt(d / 0.06f);
            for (int i = 1; i <= n; i++) if (BlockedAt(Vector3.Lerp(a, b, i / (float)n))) return false;
            return true;
        }

        public Vector3 RandomFree(float minDist, Vector3 from)
        {
            for (int t = 0; t < 200; t++)
            {
                int x = Random.Range(0, gw), y = Random.Range(0, gh);
                if (Blocked(x, y)) continue;
                var p = CellCenter(x, y);
                if (Vector3.Distance(p, from) >= minDist) return p;
            }
            return FreePoint(Vector3.zero);
        }

        /// <summary>Shortest path (smoothed) from a to b as world points on the floor; empty if unreachable.</summary>
        public List<Vector3> FindPath(Vector3 a, Vector3 b)
        {
            var path = new List<Vector3>();
            var s = NearestFree(ToCell(a));
            var t = NearestFree(ToCell(b));
            if (s == t) { path.Add(CellCenter(t.x, t.y)); return path; }
            int n = gw * gh, si = s.y * gw + s.x, ti = t.y * gw + t.x;
            var g = new float[n];
            var from = new int[n];
            var closed = new bool[n];
            for (int i = 0; i < n; i++) { g[i] = float.MaxValue; from[i] = -1; }
            var open = new List<int> { si };
            var f = new Dictionary<int, float> { [si] = H(s, t) };
            g[si] = 0f;
            while (open.Count > 0)
            {
                int bi = 0;
                for (int i = 1; i < open.Count; i++) if (f[open[i]] < f[open[bi]]) bi = i;
                int cur = open[bi];
                open.RemoveAt(bi);
                if (cur == ti) break;
                if (closed[cur]) continue;
                closed[cur] = true;
                int cx = cur % gw, cy = cur / gw;
                for (int dy = -1; dy <= 1; dy++)
                    for (int dx = -1; dx <= 1; dx++)
                    {
                        if (dx == 0 && dy == 0) continue;
                        int nx = cx + dx, ny = cy + dy;
                        if (Blocked(nx, ny)) continue;
                        if (dx != 0 && dy != 0 && (Blocked(cx + dx, cy) || Blocked(cx, cy + dy))) continue; // no corner cutting
                        int ni = ny * gw + nx;
                        float cost = g[cur] + (dx != 0 && dy != 0 ? 1.4142f : 1f);
                        if (cost >= g[ni]) continue;
                        g[ni] = cost;
                        from[ni] = cur;
                        f[ni] = cost + H(new Vector2Int(nx, ny), t);
                        open.Add(ni);
                    }
            }
            if (from[ti] < 0) return path;
            var cells = new List<Vector3>();
            for (int i = ti; i != si; i = from[i]) cells.Add(CellCenter(i % gw, i / gw));
            cells.Reverse();
            // smooth: skip points while the straight line stays clear
            Vector3 anchor = CellCenter(s.x, s.y);
            for (int i = 0; i < cells.Count; i++)
            {
                bool last = i == cells.Count - 1;
                if (last || !LineClear(anchor, cells[i + 1])) { path.Add(cells[i]); anchor = cells[i]; }
            }
            return path;
        }

        static float H(Vector2Int a, Vector2Int b)
        {
            int dx = Mathf.Abs(a.x - b.x), dy = Mathf.Abs(a.y - b.y);
            return Mathf.Max(dx, dy) + 0.4142f * Mathf.Min(dx, dy);
        }
    }
}

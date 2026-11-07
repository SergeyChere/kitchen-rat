using System;
using System.Collections.Generic;
using UnityEngine;

namespace KitchenRat
{
    // Night data exported from game/js/levels.js by tools/export_nights.mjs (Resources/Nights/NN_id.json).
    // Positions are the prototype's room coordinates in cm: x to the east, y to the south, origin at the north-west corner.

    [Serializable] public class XY { public float x, y; }
    [Serializable] public class FoodSpotData { public string type; public float x, y; public string tag; public bool hidden, floor; }
    [Serializable] public class FoodData { public FoodSpotData[] spots = new FoodSpotData[0]; public int randomCrumb, randomCheese, refill; }
    [Serializable] public class TaskData { public string text, hint, type, arg; public int n, reveal = -1; }
    [Serializable] public class TaskSet { public string goal = "Fill the nest"; public TaskData[] chain = new TaskData[0], side = new TaskData[0], secret = new TaskData[0]; }
    [Serializable] public class OwnerPlan { public string type; public float[] at = new float[0], stand = new float[0]; public float face, stay; public bool light = true; public XY[] route = new XY[0]; }
    [Serializable] public class FurnData { public string t, back, face; public float x, y, w, h, ht; public bool join, plate, dryer, dining; public int cloth, color; }
    [Serializable] public class PropData { public string t, kind, surf; public float x, y, w, h, r, spawn; public bool floor; }
    [Serializable] public class KnockData { public string kind, group, spawn; public float x, y, toX, toY; public bool trap; }
    [Serializable] public class CrackData { public string wall; public float x, y; }
    [Serializable] public class SecretData { public string kind, label; public float x, y; public bool floor, always; }
    [Serializable] public class TrapSpotData { public float x, y; public bool hidden; }
    [Serializable] public class LightData { public float x, y, h, i, r; public int c; }
    [Serializable] public class SleeperData { public string kind; public float x, y, bedH, face, sense; }
    [Serializable] public class ZoneData { public string id; public float x, y, w, h; }
    [Serializable] public class TunnelData { public int a, b; }
    [Serializable] public class WindowData { public float x, w, y, h; }
    [Serializable] public class PalData { public int fog, sky, ground, trim, ceil; public float hemi, moon; public string floor, floorA, floorB, wall, wallA, wallB; }

    [Serializable]
    public class Night
    {
        public int number, act, goal;
        public string id, name;
        public float seconds;
        public bool prologue, finale;
        public string cat = "away";
        public float catSense = 1f, sleepSense = 1f, eatTime = 40f;
        public bool catBell;
        public float[] catStart = new float[0], catBed = new float[0], bowl = new float[0], dock = new float[0], exit = new float[0];
        public bool wanted;
        public string[] threats = new string[0];
        public string starTip;
        public bool openFood, tvOff, storm;
        public float blackout;
        public string[] pups = new string[0];
        public float pupAge;
        public bool vacuumStart;
        public int poisonStart;
        public float door;
        public string lamp, decor;
        public WindowData window;
        public string teaser, blurb, startTitle, startSub, introMom;
        public string[] introPups = new string[0];
        public PalData pal;
        public FoodData food = new FoodData();
        public TaskSet tasks = new TaskSet();
        public OwnerPlan owner = new OwnerPlan();
        public FurnData[] furn = new FurnData[0];
        public PropData[] props = new PropData[0];
        public KnockData[] knocks = new KnockData[0];
        public CrackData[] cracks = new CrackData[0];
        public SecretData[] secrets = new SecretData[0];
        public TrapSpotData[] trapSpots = new TrapSpotData[0];
        public LightData[] lights = new LightData[0];
        public SleeperData[] sleepers = new SleeperData[0];
        public float[] dog = new float[0];
        public ZoneData[] zones = new ZoneData[0];
        public TunnelData[] tunnels = new TunnelData[0];

        public bool HasOwnerPlan => owner != null && !string.IsNullOrEmpty(owner.type);
        public bool HasTasks => tasks != null && tasks.chain.Length > 0;
        public int ThreatStar(string t) { int i = Array.IndexOf(threats, t); return i < 0 ? 99 : i + 1; }
        public Vector3 Pos(float[] p, float h = 0f) => p != null && p.Length >= 2 ? Nights.World(p[0], p[1], h) : Vector3.zero;
    }

    public static class Nights
    {
        public const float RoomW = 960f, RoomD = 600f;

        /// <summary>Prototype room coordinates (cm) → Unity metres, origin in the middle of the room, +Z = north.</summary>
        public static Vector3 World(float x, float y, float h = 0f) => new Vector3((x - RoomW / 2f) / 100f, h / 100f, (RoomD / 2f - y) / 100f);

        /// <summary>Unity metres → prototype room coordinates (cm).</summary>
        public static Vector2 Room(Vector3 p) => new Vector2(p.x * 100f + RoomW / 2f, RoomD / 2f - p.z * 100f);

        /// <summary>A prototype angle (radians, x east / y south) → a Unity direction.</summary>
        public static Vector3 Dir(float a) => new Vector3(Mathf.Cos(a), 0f, -Mathf.Sin(a));

        static List<string> files;

        public static List<string> Files
        {
            get
            {
                if (files != null) return files;
                files = new List<string>();
                var idx = Resources.Load<TextAsset>("Nights/index");
                if (idx) foreach (var l in idx.text.Split('\n')) if (l.Trim().Length > 0) files.Add(l.Trim());
                return files;
            }
        }

        /// <summary>Load a night by id ("kitchen", "water"…) or number ("1".."20").</summary>
        public static Night Load(string id)
        {
            foreach (var f in Files)
            {
                string fid = f.Substring(f.IndexOf('_') + 1), num = f.Substring(0, f.IndexOf('_'));
                if (fid != id && num.TrimStart('0') != id) continue;
                var ta = Resources.Load<TextAsset>("Nights/" + f);
                if (ta) return JsonUtility.FromJson<Night>(ta.text);
            }
            Debug.LogWarning("Kitchen Rat: night '" + id + "' not found in Resources/Nights");
            return new Night { id = id, name = id, goal = 10, seconds = 600f };
        }
    }
}

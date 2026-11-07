using System;
using System.Collections.Generic;

namespace KitchenRat
{
    /// <summary>
    /// The night's tasks, ported from the prototype (checkTask / keepBroken / tickTasks): a chain shown one step at a time,
    /// side tasks revealed after N steps ("keep" ones fail when broken), secrets shown once found.
    /// The game records what happened (picked tags, deliveries, knocks, flags); the tracker polls it every frame.
    /// </summary>
    public class TaskTracker
    {
        public readonly TaskSet set;
        public int step;
        public readonly HashSet<string> picked = new HashSet<string>(), delivered = new HashSet<string>(), knocked = new HashSet<string>();
        public bool deliveredAny;
        public readonly Dictionary<string, int> flags = new Dictionary<string, int>();
        public readonly HashSet<int> sideDone = new HashSet<int>(), sideFailed = new HashSet<int>(), secretDone = new HashSet<int>();

        /// <summary>Live checks the game answers: is the rat on a surface whose id starts with arg / hidden in a spot of this kind / was a "keep" broken.</summary>
        public Func<string, bool> onSurface = _ => false, hiddenIn = _ => false, keepBroken = _ => false;
        public event Action<string> Completed, Failed;

        public TaskTracker(TaskSet set) { this.set = set ?? new TaskSet(); }

        public bool HasTasks => set.chain.Length > 0;
        public bool ChainDone => step >= set.chain.Length;
        public TaskData Current => step < set.chain.Length ? set.chain[step] : null;
        public bool SideVisible(int i) => set.side[i].reveal < 0 || step >= set.side[i].reveal || sideDone.Contains(i);

        public void Flag(string name, int add = 1)
        {
            flags.TryGetValue(name, out int v);
            flags[name] = v + add;
        }

        public void SetFlag(string name) { if (!flags.ContainsKey(name)) flags[name] = 1; }
        public int FlagValue(string name) => flags.TryGetValue(name, out int v) ? v : 0;

        bool Check(TaskData t)
        {
            switch (t.type)
            {
                case "pick": return picked.Contains(t.arg);
                case "deliver": return string.IsNullOrEmpty(t.arg) ? deliveredAny : delivered.Contains(t.arg);
                case "surf": return onSurface(t.arg);
                case "hide": return hiddenIn(t.arg);
                case "knock": return knocked.Contains(t.arg);
                case "flag": return FlagValue(t.arg) > 0;
                case "count": return FlagValue(t.arg) >= t.n;
                case "pickN":
                    int k = 0;
                    foreach (var p in picked) if (p.StartsWith(t.arg)) k++;
                    return k >= t.n;
                default: return false;
            }
        }

        public void Tick()
        {
            while (Current != null && Check(Current)) { Completed?.Invoke(Current.text); step++; }
            for (int i = 0; i < set.side.Length; i++)
            {
                var t = set.side[i];
                if (sideDone.Contains(i) || sideFailed.Contains(i) || !SideVisible(i)) continue;
                if (t.type == "keep") { if (keepBroken(t.arg)) { sideFailed.Add(i); Failed?.Invoke(t.text); } }
                else if (Check(t)) { sideDone.Add(i); Completed?.Invoke(t.text); }
            }
            for (int i = 0; i < set.secret.Length; i++)
                if (!secretDone.Contains(i) && Check(set.secret[i])) { secretDone.Add(i); Completed?.Invoke("Secret: " + set.secret[i].text); }
        }

        /// <summary>When the night is won, every "keep" task that wasn't broken counts.</summary>
        public void FinishNight()
        {
            for (int i = 0; i < set.side.Length; i++)
                if (set.side[i].type == "keep" && !sideFailed.Contains(i)) sideDone.Add(i);
        }
    }
}

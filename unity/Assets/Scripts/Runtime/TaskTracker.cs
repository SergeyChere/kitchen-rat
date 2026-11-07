using System;
using System.Collections.Generic;

namespace KitchenRat
{
    /// <summary>
    /// The night's tasks: a chain shown one step at a time, side tasks revealed after N steps, secret tasks shown once done.
    /// Game events are reported as (check, arg); a step that was already satisfied earlier completes as soon as it comes up.
    /// </summary>
    public class TaskTracker
    {
        public readonly NightDef night;
        public int step;
        public readonly HashSet<int> sideDone = new HashSet<int>(), sideFailed = new HashSet<int>(), secretDone = new HashSet<int>();
        public event Action<string> Completed;
        public event Action<string> Failed;

        readonly HashSet<string> history = new HashSet<string>();
        readonly List<string> picked = new List<string>();

        public TaskTracker(NightDef night) { this.night = night; }

        public TaskDef Current => step < night.chain.Length ? night.chain[step] : null;

        public void Report(Check c, string arg)
        {
            arg = arg ?? "";
            if (c == Check.Pick) picked.Add(arg);
            history.Add(c + ":" + arg);

            for (int i = 0; i < night.side.Length; i++)
            {
                var t = night.side[i];
                if (sideDone.Contains(i) || sideFailed.Contains(i)) continue;
                if (t.check == Check.Keep)
                {
                    if (c == Check.Knock && arg == t.arg) { sideFailed.Add(i); Failed?.Invoke(t.text); }
                }
                else if (Matches(t, c, arg)) { sideDone.Add(i); Completed?.Invoke(t.text); }
            }
            for (int i = 0; i < night.secret.Length; i++)
                if (!secretDone.Contains(i) && Matches(night.secret[i], c, arg)) { secretDone.Add(i); Completed?.Invoke("Secret: " + night.secret[i].text); }

            if (Current != null && Matches(Current, c, arg)) Advance();
        }

        void Advance()
        {
            Completed?.Invoke(Current.text);
            step++;
            while (Current != null && AlreadyDone(Current)) { Completed?.Invoke(Current.text); step++; }
        }

        bool AlreadyDone(TaskDef t)
        {
            switch (t.check)
            {
                case Check.PickN: return Count(t.arg) >= t.n;
                case Check.Deliver: return !string.IsNullOrEmpty(t.arg) && history.Contains("Deliver:" + t.arg);
                case Check.Keep: return false;
                case Check.Surf:
                    foreach (var h in history) if (h.StartsWith("Surf:" + t.arg)) return true;
                    return false;
                default: return history.Contains(t.check + ":" + (t.arg ?? ""));
            }
        }

        int Count(string prefix)
        {
            int k = 0;
            foreach (var p in picked) if (p.StartsWith(prefix ?? "")) k++;
            return k;
        }

        bool Matches(TaskDef t, Check c, string arg)
        {
            switch (t.check)
            {
                case Check.Deliver: return c == Check.Deliver && (string.IsNullOrEmpty(t.arg) || arg == t.arg);
                case Check.Surf: return c == Check.Surf && arg.StartsWith(t.arg ?? "");
                case Check.PickN: return c == Check.Pick && arg.StartsWith(t.arg ?? "") && Count(t.arg) >= t.n;
                case Check.Keep: return false;
                default: return c == t.check && arg == (t.arg ?? "");
            }
        }

        /// <summary>At dawn / when the nest is full: every "keep" task that wasn't broken counts as done.</summary>
        public void FinishNight()
        {
            for (int i = 0; i < night.side.Length; i++)
                if (night.side[i].check == Check.Keep && !sideFailed.Contains(i)) sideDone.Add(i);
        }

        public bool SideVisible(int i) => step >= night.side[i].reveal;
    }
}

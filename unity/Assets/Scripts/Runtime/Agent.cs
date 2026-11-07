using System.Collections.Generic;
using UnityEngine;

namespace KitchenRat
{
    /// <summary>Something that walks the A* grid on the floor (cat, owner): follows a path, turns, picks animations.</summary>
    public abstract class Agent : MonoBehaviour
    {
        public ClipPlayer anim;
        public float eyeHeight = 0.25f;
        [System.NonSerialized] public List<Vector3> path = new List<Vector3>();
        public float Speed { get; protected set; }

        protected GameManager G => GameManager.I;
        protected RatController Rat => GameManager.I.rat;
        protected NavGrid Grid => GameManager.I.Grid;

        protected void PathTo(Vector3 target) { path = Grid.FindPath(transform.position, target); }

        /// <summary>Walk along the path. Returns false when there is nothing left to walk.</summary>
        protected bool Follow(float speed, float dt)
        {
            if (path.Count == 0) return false;
            Vector3 p = transform.position, t = path[0];
            t.y = p.y;
            Vector3 d = t - p;
            float dist = d.magnitude;
            if (dist < 0.03f)
            {
                path.RemoveAt(0);
                return path.Count > 0;
            }
            float step = Mathf.Min(dist, speed * dt);
            transform.position = p + d / dist * step;
            Turn(d, dt * 10f);
            Speed = speed;
            return true;
        }

        protected void Turn(Vector3 dir, float k)
        {
            dir.y = 0f;
            if (dir.sqrMagnitude < 1e-5f) return;
            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(dir), Mathf.Clamp01(k));
        }

        protected Vector3 ToRat => Rat.transform.position - transform.position;
        protected float DistRat { get { var d = ToRat; d.y = 0f; return d.magnitude; } }

        /// <summary>Angle (degrees) between where we look (+ an extra yaw) and the rat.</summary>
        protected float AngleToRat(float extraYaw = 0f)
        {
            var d = ToRat;
            d.y = 0f;
            return Vector3.Angle(Quaternion.Euler(0f, extraYaw, 0f) * transform.forward, d);
        }

        protected bool LineOfSight()
        {
            Vector3 eye = transform.position + Vector3.up * eyeHeight, target = Rat.transform.position + Vector3.up * 0.06f;
            return !Physics.Linecast(eye, target, RatController.Mask, QueryTriggerInteraction.Ignore);
        }

        protected void Play(string clip, float fade = 0.2f) { if (anim) anim.Play(clip, fade); }
    }
}

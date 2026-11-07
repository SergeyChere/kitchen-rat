using UnityEngine;

/// <summary>
/// Лучи для зрения кота и камеры. Игнорирует триггеры, невидимые барьеры для кота,
/// а также самих крысу и кота.
/// </summary>
public static class Sight
{
    public static bool Blocks(Collider c)
    {
        if (c.isTrigger) return false;
        if (c.GetComponent<CatBlocker>() != null) return false;
        if (c.GetComponentInParent<RatController>() != null) return false;
        if (c.GetComponentInParent<CatAI>() != null) return false;
        return true;
    }

    /// <summary>Есть ли прямая видимость между двумя точками.</summary>
    public static bool Clear(Vector3 from, Vector3 to)
    {
        Vector3 d = to - from;
        float len = d.magnitude;
        if (len < 1e-4f) return true;
        var hits = Physics.RaycastAll(from, d / len, len, ~0, QueryTriggerInteraction.Ignore);
        foreach (var h in hits)
            if (Blocks(h.collider)) return false;
        return true;
    }

    /// <summary>Расстояние до первого препятствия по лучу (или max).</summary>
    public static float Distance(Vector3 from, Vector3 dir, float max)
    {
        float best = max;
        var hits = Physics.RaycastAll(from, dir, max, ~0, QueryTriggerInteraction.Ignore);
        foreach (var h in hits)
            if (h.distance < best && Blocks(h.collider)) best = h.distance;
        return best;
    }

    /// <summary>То же, но толстым лучом (для камеры, чтобы не залезала в мебель).</summary>
    public static float SphereDistance(Vector3 from, Vector3 dir, float radius, float max)
    {
        float best = max;
        var hits = Physics.SphereCastAll(from, radius, dir, max, ~0, QueryTriggerInteraction.Ignore);
        foreach (var h in hits)
            if (h.distance > 0f && h.distance < best && Blocks(h.collider)) best = h.distance;
        return best;
    }

    public static float FlatDistance(Vector3 a, Vector3 b)
    {
        a.y = 0f; b.y = 0f;
        return Vector3.Distance(a, b);
    }
}

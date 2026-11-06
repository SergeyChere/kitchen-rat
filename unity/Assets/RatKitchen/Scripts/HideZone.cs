using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Укрытие: пока крыса внутри этого объёма (под столом, стулом, полкой), кот её не видит.
/// </summary>
[RequireComponent(typeof(BoxCollider))]
public class HideZone : MonoBehaviour
{
    public static readonly List<HideZone> All = new List<HideZone>();
    BoxCollider box;

    void Awake()
    {
        box = GetComponent<BoxCollider>();
        box.isTrigger = true;
    }

    void OnEnable() { All.Add(this); }
    void OnDisable() { All.Remove(this); }

    public bool Contains(Vector3 p) { return box.bounds.Contains(p); }

    public static bool Any(Vector3 p)
    {
        foreach (var h in All)
            if (h.Contains(p)) return true;
        return false;
    }
}

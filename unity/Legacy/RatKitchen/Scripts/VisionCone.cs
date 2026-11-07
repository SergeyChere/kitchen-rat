using UnityEngine;

/// <summary>Полупрозрачный конус зрения кота на полу. Обрезается мебелью.</summary>
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class VisionCone : MonoBehaviour
{
    public CatAI cat;
    public int segments = 28;
    public Color calm = new Color(0.86f, 0.86f, 0.92f, 0.14f);
    public Color wary = new Color(0.95f, 0.76f, 0.3f, 0.18f);
    public Color chase = new Color(0.91f, 0.4f, 0.29f, 0.26f);

    Mesh mesh;
    Vector3[] verts;
    Material mat;

    void Awake()
    {
        mesh = new Mesh { name = "VisionCone" };
        mesh.MarkDynamic();
        GetComponent<MeshFilter>().mesh = mesh;
        verts = new Vector3[segments + 2];
        var tris = new int[segments * 3];
        for (int i = 0; i < segments; i++)
        {
            tris[i * 3] = 0; tris[i * 3 + 1] = i + 1; tris[i * 3 + 2] = i + 2;
        }
        mesh.vertices = verts;
        mesh.triangles = tris;
        mat = GetComponent<MeshRenderer>().material;
    }

    void LateUpdate()
    {
        if (!cat) return;
        transform.position = cat.transform.position + Vector3.up * 0.008f;
        transform.rotation = Quaternion.identity;

        Vector3 origin = cat.transform.position + Vector3.up * 0.06f;
        float baseYaw = cat.transform.eulerAngles.y;
        verts[0] = Vector3.zero;
        for (int i = 0; i <= segments; i++)
        {
            float a = baseYaw - cat.viewHalfAngle + 2f * cat.viewHalfAngle * i / segments;
            Vector3 dir = Quaternion.Euler(0f, a, 0f) * Vector3.forward;
            verts[i + 1] = dir * Sight.Distance(origin, dir, cat.viewDistance);
        }
        mesh.vertices = verts;
        mesh.RecalculateBounds();

        mat.color = cat.CurrentMode == CatAI.Mode.Chase ? chase : cat.Alert > 0.3f ? wary : calm;
    }
}

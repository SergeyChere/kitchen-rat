using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Animations;
using UnityEngine.Playables;

namespace KitchenRat
{
    /// <summary>
    /// Plays a character's animation clips by name with cross-fades, without an Animator Controller asset.
    /// Clip names come from the Blender actions: "walk", "run", "sneak", "sleep"…
    /// </summary>
    [RequireComponent(typeof(Animator))]
    public class ClipPlayer : MonoBehaviour
    {
        public List<AnimationClip> clips = new List<AnimationClip>();
        public string startClip = "idle";

        PlayableGraph graph;
        AnimationMixerPlayable mixer;
        readonly Dictionary<string, int> index = new Dictionary<string, int>();
        float[] weights;
        int current = -1;
        float fade = 0.15f;

        public string Current => current >= 0 ? Short(clips[current].name) : null;

        public static string Short(string clipName)
        {
            int i = clipName.LastIndexOf('|');
            return i >= 0 ? clipName.Substring(i + 1) : clipName;
        }

        void Awake()
        {
            var animator = GetComponent<Animator>();
            animator.applyRootMotion = false;
            graph = PlayableGraph.Create(name + "_clips");
            graph.SetTimeUpdateMode(DirectorUpdateMode.GameTime);
            var output = AnimationPlayableOutput.Create(graph, "anim", animator);
            mixer = AnimationMixerPlayable.Create(graph, clips.Count);
            output.SetSourcePlayable(mixer);
            weights = new float[clips.Count];
            for (int i = 0; i < clips.Count; i++)
            {
                var p = AnimationClipPlayable.Create(graph, clips[i]);
                graph.Connect(p, 0, mixer, i);
                mixer.SetInputWeight(i, 0f);
                index[Short(clips[i].name)] = i;
            }
            graph.Play();
            if (!string.IsNullOrEmpty(startClip)) Play(startClip, 0f);
        }

        public bool Has(string clip) => index.ContainsKey(clip);

        /// <summary>Cross-fade to a clip. Calling it again with the same clip does nothing unless restart is true.</summary>
        public void Play(string clip, float fadeTime = 0.15f, bool restart = false)
        {
            if (!index.TryGetValue(clip, out int i)) return;
            if (i == current && !restart) return;
            if (restart || weights[i] < 0.01f) mixer.GetInput(i).SetTime(0);
            current = i;
            fade = fadeTime;
            if (fade <= 0f)
            {
                for (int k = 0; k < weights.Length; k++) weights[k] = k == i ? 1f : 0f;
                Apply();
            }
        }

        public float Speed
        {
            set { if (mixer.IsValid()) mixer.SetSpeed(value); }
        }

        void Update()
        {
            if (current < 0) return;
            float step = fade <= 0f ? 1f : Time.deltaTime / fade;
            for (int i = 0; i < weights.Length; i++) weights[i] = Mathf.MoveTowards(weights[i], i == current ? 1f : 0f, step);
            Apply();
        }

        void Apply()
        {
            float sum = 0f;
            foreach (var w in weights) sum += w;
            if (sum <= 0f) return;
            for (int i = 0; i < weights.Length; i++) mixer.SetInputWeight(i, weights[i] / sum);
        }

        void OnDestroy()
        {
            if (graph.IsValid()) graph.Destroy();
        }
    }
}

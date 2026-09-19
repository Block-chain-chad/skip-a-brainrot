"""NPC-01 kit harness: runs the real Luau modules from game-src/npc-kit under a
plain Lua 5.1 VM (lupa) with the Roblox API stub in rbx_stub.lua.

Nothing here touches Studio. The DataModel is a tree of tables; "building"
Gianluca means the same NpcForge code runs and produces the same instance tree
it would produce in Edit mode, which the tests then inspect.

    from npc_kit.harness import Harness
    H = Harness()
    forge = H.require("ServerStorage/NpcForge")
    model, report = forge.Build("Gianluca", H.table(blockout=True))
"""
from __future__ import annotations

import os
from pathlib import Path

from lupa import lua51

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
KIT = REPO / "game-src" / "npc-kit"

# DataModel path (under game) -> (class, file relative to game-src/npc-kit)
SCRIPTS = {
    "ReplicatedStorage/Modules/NpcKit/NpcRigSpec": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcRigSpec.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcFaceConfig": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcFaceConfig.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcLibrary": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcLibrary.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcFamilies": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcFamilies.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcWorldThemes": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcWorldThemes.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcMotionConfig": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcMotionConfig.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcLodProfiles": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcLodProfiles.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcMotion": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcMotion.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcLife": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcLife.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcCharacters/Gianluca": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcCharacters/Gianluca.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcCharacters/VeteranBombardiro": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcCharacters/VeteranBombardiro.lua"),
    "ReplicatedStorage/Modules/NpcKit/NpcCharacters/Villager_Valley_01": ("ModuleScript", "ReplicatedStorage/Modules/NpcKit/NpcCharacters/Villager_Valley_01.lua"),
    "ServerStorage/NpcForge": ("ModuleScript", "ServerStorage/NpcForge.lua"),
    "ServerStorage/NpcBudget": ("ModuleScript", "ServerStorage/NpcBudget.lua"),
    "StarterPlayer/StarterPlayerScripts/NpcLifeClient": ("LocalScript", "StarterPlayer/StarterPlayerScripts/NpcLifeClient.client.lua"),
}
FOLDERS = ["ReplicatedStorage/Modules", "ReplicatedStorage/Modules/NpcKit", "ReplicatedStorage/Modules/NpcKit/NpcCharacters"]


def all_lua_files() -> list[Path]:
    return sorted(KIT.rglob("*.lua"))


class Harness:
    def __init__(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        stub_path = (HERE / "rbx_stub.lua").as_posix()
        self.stub = self.lua.execute(f'return dofile("{stub_path}")')
        self.g = self.lua.globals()
        self.game = self.stub.game
        self._instances = {}
        self._build_tree()

    # ----- tree ---------------------------------------------------------------
    def _get(self, path: str):
        node = self.game
        for seg in path.split("/"):
            child = node.FindFirstChild(node, seg)
            if child is None:
                raise KeyError(path)
            node = child
        return node

    def _ensure_folder(self, path: str):
        parts = path.split("/")
        node = self.game
        for seg in parts:
            child = node.FindFirstChild(node, seg)
            if child is None:
                child = self.stub.Instance.new("Folder")
                child.Name = seg
                child.Parent = node
            node = child
        return node

    def _build_tree(self):
        for f in FOLDERS:
            self._ensure_folder(f)
        for dm_path, (cls, rel) in SCRIPTS.items():
            parent_path, name = dm_path.rsplit("/", 1)
            parent = self._ensure_folder(parent_path) if "/" in parent_path else self._get(parent_path)
            inst = self.stub.Instance.new(cls)
            inst.Name = name
            inst.Parent = parent
            file = KIT / rel
            assert file.exists(), file
            self.stub.registerScript(inst, file.as_posix())
            self._instances[dm_path] = inst

    # ----- helpers ------------------------------------------------------------
    def instance(self, dm_path: str):
        return self._instances[dm_path]

    def require(self, dm_path: str):
        return self.stub.require(self._instances[dm_path])

    def run_local_script(self, dm_path: str):
        chunk = self.stub.loadScript(self._instances[dm_path])
        return chunk()

    def table(self, **kw):
        t = self.lua.table()
        for k, v in kw.items():
            t[k] = v
        return t

    def lua_list(self, t) -> list:
        return [t[i] for i in range(1, len(t) + 1)]

    def descendants(self, model) -> list:
        return self.lua_list(model.GetDescendants(model))

    def children_names(self, inst) -> list[str]:
        return [c.Name for c in self.lua_list(inst.GetChildren(inst))]

    def find(self, inst, name: str, recursive: bool = True):
        return inst.FindFirstChild(inst, name, recursive)

    def tick(self, dt: float = 1 / 60):
        self.stub.clock = self.stub.clock + dt
        self.stub.RunService.Heartbeat.Fire(self.stub.RunService.Heartbeat, dt)

    def log(self) -> list[str]:
        return self.lua_list(self.stub.log)

    def v3t(self, v) -> tuple:
        return (round(v.X, 6), round(v.Y, 6), round(v.Z, 6))

    def same(self, a, b) -> bool:
        """Lua-side identity/equality (lupa wrappers never compare equal in Python)."""
        return bool(self.lua.eval("function(a, b) return a == b end")(a, b))

    def mul(self, a, b):
        """Lua-side `a * b` (CFrame * CFrame, CFrame * Vector3)."""
        return self.lua.eval("function(a, b) return a * b end")(a, b)

    def world_aabb(self, part) -> tuple:
        """World axis-aligned bounds of a possibly rotated part (8 corners through its CFrame)."""
        f = self.lua.eval("""function(p)
            local s = p.Size / 2
            local lo, hi = nil, nil
            for _, sx in ipairs({-1, 1}) do for _, sy in ipairs({-1, 1}) do for _, sz in ipairs({-1, 1}) do
                local c = p.CFrame * Vector3.new(sx * s.X, sy * s.Y, sz * s.Z)
                if not lo then lo, hi = c, c else
                    lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
                    hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) end
            end end end
            return lo.X, lo.Y, lo.Z, hi.X, hi.Y, hi.Z
        end""")
        x0, y0, z0, x1, y1, z1 = f(part)
        return (x0, y0, z0), (x1, y1, z1)

    def dist(self, a, b) -> float:
        return self.lua.eval("function(a, b) return (a - b).Magnitude end")(a, b)

    def kit_modules(self):
        return self.table(
            RigSpec=self.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec"),
            FaceConfig=self.require("ReplicatedStorage/Modules/NpcKit/NpcFaceConfig"),
            Library=self.require("ReplicatedStorage/Modules/NpcKit/NpcLibrary"),
            Families=self.require("ReplicatedStorage/Modules/NpcKit/NpcFamilies"),
            Themes=self.require("ReplicatedStorage/Modules/NpcKit/NpcWorldThemes"),
            MotionConfig=self.require("ReplicatedStorage/Modules/NpcKit/NpcMotionConfig"),
            LodProfiles=self.require("ReplicatedStorage/Modules/NpcKit/NpcLodProfiles"),
            Motion=self.require("ReplicatedStorage/Modules/NpcKit/NpcMotion"),
            Characters=self._get("ReplicatedStorage/Modules/NpcKit/NpcCharacters"),
        )

    def forge(self):
        f = self.require("ServerStorage/NpcForge")
        f._setKit(self.kit_modules())
        return f

    # a fake pack-style species template: RootPart + FakeRootPart + 3 MeshParts on Motor6D
    def make_species_template(self, name="Bombardiro Crocodilo", parent_folder=True):
        I = self.stub.Instance
        m = I.new("Model")
        m.Name = name
        root = I.new("Part"); root.Name = "RootPart"; root.Transparency = 1; root.Size = self.stub.Vector3.new(4, 4, 6); root.Parent = m
        fake = I.new("Part"); fake.Name = "FakeRootPart"; fake.Transparency = 1; fake.Size = self.stub.Vector3.new(1, 1, 1); fake.Parent = m
        m.PrimaryPart = root
        w = I.new("WeldConstraint"); w.Part0 = root; w.Part1 = fake; w.Parent = fake
        # a crocodile-plane STAND-IN (body slab, long snout to -Z, wings, tail) -- not the pack asset
        for pname, size, off in [("Body", (4, 2.2, 6), (0, 0, 0)), ("Head", (1.8, 1.4, 3), (0, 0.3, -4.4)),
                                 ("WingL", (5, 0.3, 2), (-4.4, 0.9, 0)), ("WingR", (5, 0.3, 2), (4.4, 0.9, 0)),
                                 ("Tail", (1, 1, 3.5), (0, -0.2, 4.5)), ("FinL", (0.3, 1.2, 1.2), (-0.9, 1.2, 1.5)), ("FinR", (0.3, 1.2, 1.2), (0.9, 1.2, 1.5))]:
            p = I.new("MeshPart"); p.Name = pname; p.Size = self.stub.Vector3.new(*size); p.CFrame = self.stub.CFrame.new(*off)
            p.Color = self.stub.Color3.fromRGB(90, 140, 86); p.Parent = m
            j = I.new("Motor6D"); j.Name = pname + "Joint"; j.Part0 = fake; j.Part1 = p; j.C0 = self.stub.CFrame.new(*off); j.Parent = p
        fx = I.new("Part"); fx.Name = "VfxInstance"; fx.Transparency = 1; fx.Parent = m
        for i in range(3):
            e = I.new("ParticleEmitter"); e.Name = f"Aura{i}"; e.Parent = fx
        s = I.new("Sound"); s.Parent = root
        m.SetAttribute(m, "HeightScale", 1.25)
        if parent_folder:
            folder = self.find(self.stub.services.ReplicatedStorage, "BrainrotModels", False)
            if folder is None:
                folder = I.new("Folder"); folder.Name = "BrainrotModels"; folder.Parent = self.stub.services.ReplicatedStorage
            m.Parent = folder
        return m

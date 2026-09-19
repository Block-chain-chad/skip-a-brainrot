import pytest

from npc_kit.harness import Harness


@pytest.fixture
def H():
    return Harness()


def build_gianluca(H, **opts):
    forge = H.forge()
    o = H.table(blockout=True, **opts)
    model, report = forge.Build("Gianluca", o)
    assert model is not None, f"Gianluca failed the budget: {rows(report)}"
    return model, report


def rows(report):
    if report is None or report.budget is None:
        return "no budget"
    out = []
    b = report.budget
    for i in range(1, len(b.rows) + 1):
        r = b.rows[i]
        out.append(f"{r.name}={r.value}/{r.limit}:{r.status}")
    return ", ".join(out)

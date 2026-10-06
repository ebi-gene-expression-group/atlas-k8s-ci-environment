"""GXA browser scenarios.

Add a module named test_<scenario>.py in this package. Pytest collects every
function named test_*. Example:

    def test_plots(page, gxa):
        accession = gxa.baseline_accession()
        gxa.open(page, f"/experiments/{accession}/Plots")
        gxa.expect_experiment(page, accession)
"""

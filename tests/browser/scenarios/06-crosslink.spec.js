"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const fixtures_1 = require("../fixtures");
(0, fixtures_1.test)('35. E-PROT-29 and E-MTAB-2836 each link to the other.', async ({ page, gxa }) => {
    const pairs = [
        ['E-PROT-29', 'E-MTAB-2836'],
        ['E-MTAB-2836', 'E-PROT-29'],
    ];
    for (const [accession, other] of pairs) {
        await gxa.open(page, `/experiments/${accession}/Results`);
        await gxa.expectExperiment(page, accession);
        (0, fixtures_1.expect)(await page.locator(`a[href*='${other}']`).count(), `${accession} did not link to ${other}`).toBeGreaterThan(0);
    }
});

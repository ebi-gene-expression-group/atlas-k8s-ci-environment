"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const test_1 = require("@playwright/test");
const INDEX = 'http://ftp.ebi.ac.uk/pub/databases/microarray/data/atlas/indices/';
async function listingNames(page) {
    return page.locator('a').evaluateAll((els) => els.map((el) => el.getAttribute('href') || ''));
}
(0, test_1.test)('FTP indices grouped by experiment type, file type, and species.', async ({ page }) => {
    await page.goto(INDEX, { waitUntil: 'domcontentloaded' });
    const names = await listingNames(page);
    for (const directory of ['by-experiment-type/', 'by-file-type/', 'by-species/']) {
        (0, test_1.expect)(names, directory).toContain(directory);
    }
    await page.goto(`${INDEX}by-experiment-type/`, { waitUntil: 'domcontentloaded' });
    const experimentTypes = await listingNames(page);
    (0, test_1.expect)(experimentTypes).toContain('baseline/');
    (0, test_1.expect)(experimentTypes).toContain('differential/');
    for (const child of ['baseline/', 'differential/']) {
        await page.goto(`${INDEX}by-experiment-type/${child}`, { waitUntil: 'domcontentloaded' });
        const children = (await listingNames(page)).filter((name) => name !== '../' && name !== '/');
        (0, test_1.expect)(children.length, child).toBeGreaterThan(0);
    }
    await page.goto(`${INDEX}by-file-type/`, { waitUntil: 'domcontentloaded' });
    const fileTypes = await listingNames(page);
    (0, test_1.expect)(fileTypes).toContain('sdrf/');
    (0, test_1.expect)(fileTypes).toContain('tpms/');
    await page.goto(`${INDEX}by-species/homo_sapiens/`, { waitUntil: 'domcontentloaded' });
    const accessions = (await listingNames(page)).filter((name) => name.startsWith('E-'));
    (0, test_1.expect)(accessions.length, 'homo_sapiens/ listed no experiment accessions').toBeGreaterThan(0);
    await (0, test_1.expect)(page.getByRole('link', { name: accessions[0].replace(/\/$/, '') })).toBeVisible();
});

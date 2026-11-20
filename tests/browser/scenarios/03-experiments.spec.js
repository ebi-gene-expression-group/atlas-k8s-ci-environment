"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const fixtures_1 = require("../fixtures");
function experimentLinks(page) {
    return page.locator("#experiments a[href*='/experiments/E-'][href*='/Results']");
}
async function waitForRows(page) {
    await experimentLinks(page).first().waitFor({ state: 'visible', timeout: 10_000 });
}
async function accessions(page) {
    const hrefs = await experimentLinks(page).evaluateAll((els) => els.map((el) => el.getAttribute('href') || ''));
    return hrefs.flatMap((href) => href.match(/(E-[A-Z0-9-]+)/)?.[1] ?? []);
}
async function titles(page) {
    return (await experimentLinks(page).allInnerTexts()).map((text) => text.trim()).filter(Boolean);
}
(0, fixtures_1.test)('13. First data row has type, species, title, and assays.', async ({ page, gxa }) => {
    await gxa.open(page, '/experiments');
    await (0, fixtures_1.expect)(page).toHaveTitle(/Experiments/);
    await waitForRows(page);
    const row = experimentLinks(page).first().locator("xpath=ancestor::div[contains(@class, 'ub-b-btm_1px-solid-EDF0F2')][1]");
    await (0, fixtures_1.expect)(row.locator("img[alt$='experiment']")).toBeVisible();
    const title = (await row.locator("a[href*='/experiments/E-']").first().innerText()).trim();
    (0, fixtures_1.expect)(title, 'title cell was empty').toBeTruthy();
    const text = await row.innerText();
    (0, fixtures_1.expect)(text, `species missing from ${text}`).toMatch(/[A-Z][a-z]+ [a-z]+/);
    (0, fixtures_1.expect)(text, `assays missing from ${text}`).toMatch(/\b\d+\b/);
});
(0, fixtures_1.test)('14. Title search for one word narrows the rows.', async ({ page, gxa }) => {
    await gxa.open(page, '/experiments');
    await waitForRows(page);
    const before = await accessions(page);
    const word = 'Arabidopsis';
    const titleFilter = page.locator("#experiments input[placeholder='Title']");
    await titleFilter.click();
    await titleFilter.pressSequentially(word, { delay: 20 });
    await page.waitForFunction((expected) => {
        const links = [...document.querySelectorAll("#experiments a[href*='/Results']")];
        return (links.length > 0 &&
            links.every((link) => (link.textContent || '').toLowerCase().includes(String(expected).toLowerCase())));
    }, word, { timeout: 10_000 });
    const shown = await titles(page);
    (0, fixtures_1.expect)(shown.length).toBeGreaterThan(0);
    (0, fixtures_1.expect)(shown.every((title) => title.toLowerCase().includes(word.toLowerCase()))).toBeTruthy();
    (0, fixtures_1.expect)(await accessions(page)).not.toEqual(before);
});
(0, fixtures_1.test)('15. A second word is applied; both words appear in the remaining titles.', async ({ page, gxa }) => {
    await gxa.open(page, '/experiments');
    await waitForRows(page);
    const before = await titles(page);
    const query = 'soybean seeds';
    const titleFilter = page.locator("#experiments input[placeholder='Title']");
    await titleFilter.click();
    await titleFilter.pressSequentially(query, { delay: 20 });
    await page.waitForFunction(([expected, previous]) => {
        const input = document.querySelector("#experiments input[placeholder='Title']");
        if (!input || input.value !== expected)
            return false;
        const shown = [...document.querySelectorAll("#experiments a[href*='/Results']")]
            .map((link) => (link.textContent || '').trim())
            .filter(Boolean);
        return shown.length > 0 && shown.join('\n') !== previous;
    }, [query, before.join('\n')], { timeout: 10_000 });
    const shown = await titles(page);
    (0, fixtures_1.expect)(shown.length).toBeGreaterThan(0);
    (0, fixtures_1.expect)(shown, 'title search did not change the visible rows').not.toEqual(before);
    for (const title of shown) {
        const lowered = title.toLowerCase();
        (0, fixtures_1.expect)(lowered.includes('soybean') && lowered.includes('seeds'), title).toBeTruthy();
    }
});
(0, fixtures_1.test)('16. Sort by the Type column and the order changes.', async ({ page, gxa }) => {
    await gxa.open(page, '/experiments');
    await waitForRows(page);
    const before = await accessions(page);
    const header = page.locator('#experiments').getByText('Type', { exact: true });
    await header.click();
    await page.waitForTimeout(500);
    if ((await accessions(page)).join() === before.join()) {
        await header.click();
        await page.waitForTimeout(500);
    }
    (0, fixtures_1.expect)(await accessions(page)).not.toEqual(before);
});
(0, fixtures_1.test)('17. Check one download box and the Download N entries control appears.', async ({ page, gxa }) => {
    await gxa.open(page, '/experiments');
    await waitForRows(page);
    await page.locator('#experiments input[type=checkbox]').first().click({ force: true });
    await (0, fixtures_1.expect)(page.getByText(/Download \d+ entr/)).toBeVisible();
});
(0, fixtures_1.test)('18. Change page and the visible accession changes.', async ({ page, gxa }) => {
    await gxa.open(page, '/experiments');
    await waitForRows(page);
    const before = await accessions(page);
    await page.locator('#experiments').getByText('Next', { exact: true }).click();
    await page.waitForFunction((previous) => {
        const link = document.querySelector("#experiments a[href*='/Results']");
        return link && !(link.getAttribute('href') || '').includes(String(previous));
    }, before[0], { timeout: 10_000 });
    (0, fixtures_1.expect)((await accessions(page))[0]).not.toBe(before[0]);
});

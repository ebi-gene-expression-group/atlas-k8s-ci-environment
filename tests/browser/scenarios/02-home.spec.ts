import { test, expect } from '../fixtures';

test('Home page renders the search form.', async ({ page, gxa }) => {
  await gxa.open(page, '/home');
  await expect(page).toHaveTitle(/Home/);
  await page.locator('#search-atlas').waitFor({ state: 'visible' });
  await page.locator('#home-search-gene-query-input').waitFor({ state: 'visible' });
  await page.locator('#experiments-summary-panel').waitFor({ state: 'attached' });
});

test('10. Check/Select Featured Experiments (GTEx, EDTL, PCAWG).', async ({ page, gxa }) => {
  await gxa.open(page, '/home');
  await gxa.dismissBanner(page);
  const featured = page.locator('#featured');
  for (const fragment of ['E-GTEX-8', '/edtl/experiments', 'E-MTAB-5200', 'E-MTAB-5423']) {
    await expect(featured.locator(`a[href*='${fragment}']`).first(), fragment).toBeVisible({ timeout: 60_000 });
  }
  for (const accession of ['E-MTAB-5200', 'E-MTAB-5423']) {
    await gxa.open(page, `/experiments/${accession}/Results`);
    await gxa.expectExperiment(page, accession);
    await gxa.expectHeatmap(page);
  }
});

test('11. Links to Tools.', async ({ page, gxa }) => {
  await gxa.open(page, '/home');
  const links = page.locator('#tools a');
  await links.first().waitFor({ state: 'visible' });
  const hrefs: string[] = [];
  for (let index = 0; index < (await links.count()); index += 1) {
    hrefs.push((await links.nth(index).getAttribute('href')) ?? '');
  }
  expect(hrefs.length).toBeGreaterThan(0);
  expect(hrefs.every((href) => href.startsWith('http'))).toBeTruthy();
  const inApp = hrefs.find((href) => href.startsWith(gxa.baseUrl)) ?? hrefs[0];
  const response = await page.request.get(inApp, { timeout: 30_000 });
  expect(response.ok(), `${inApp} returned HTTP ${response.status()}`).toBeTruthy();
});

test('12. Links to publications.', async ({ page, gxa }) => {
  await gxa.open(page, '/home');
  const links = page.locator('#publication-list a');
  await links.first().waitFor({ state: 'visible' });
  const hrefs: string[] = [];
  for (let index = 0; index < (await links.count()); index += 1) {
    hrefs.push((await links.nth(index).getAttribute('href')) ?? '');
  }
  expect(hrefs.length).toBeGreaterThanOrEqual(1);
  expect(hrefs.every((href) => href.startsWith('http'))).toBeTruthy();
});

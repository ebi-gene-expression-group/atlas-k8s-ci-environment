import { test as base, expect, type Page, type Response } from '@playwright/test';

type Experiment = {
  experimentAccession?: string;
  rawExperimentType?: string;
  species?: string;
  numberOfAssays?: number;
};

let experimentList: Experiment[] | null = null;

export class Gxa {
  readonly baseUrl: string;
  private baseline: string | null = null;
  private differential = new Map<string, string>();

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  async baselineAccession(): Promise<string> {
    if (this.baseline) return this.baseline;
    const experiments = await this.experiments();
    const chosen =
      experiments.find((item) => item.rawExperimentType === 'RNASEQ_MRNA_BASELINE') ?? experiments[0];
    const accession = chosen?.experimentAccession ?? '';
    expect(accession, 'experimentAccession missing on selected experiment').toBeTruthy();
    this.baseline = accession;
    return accession;
  }

  differentialMicroarrayAccession(): Promise<string> {
    return this.differentialAccession('MICROARRAY_1COLOUR_MRNA_DIFFERENTIAL');
  }

  differentialRnaseqAccession(): Promise<string> {
    return this.differentialAccession('RNASEQ_MRNA_DIFFERENTIAL');
  }

  async open(page: Page, path: string): Promise<Response> {
    const url = `${this.baseUrl}${path.startsWith('/') ? path : `/${path}`}`;
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120_000 });
    expect(response, `no response for ${url}`).toBeTruthy();
    expect(response!.ok(), `${url} returned HTTP ${response!.status()}`).toBeTruthy();
    await expect(page.locator('h4', { hasText: 'Error:' })).toHaveCount(0);
    return response!;
  }

  async expectExperiment(page: Page, accession: string): Promise<void> {
    expect(page.url(), `${accession} missing from ${page.url()}`).toContain(accession);
    await page.locator('#experimentDescription').waitFor({ state: 'visible' });
    await page.locator('#experiment-page').waitFor({ state: 'attached' });
    expect(await page.content(), `${accession} missing from experiment page HTML`).toContain(accession);
  }

  async expectSearchResults(page: Page, example: string): Promise<void> {
    await expect(page).toHaveTitle(/Search results/);
    await expect(page.locator('h4', { hasText: 'Error:' })).toHaveCount(0);
    await expect(page.getByText('Sorry, we could not find results matching your search criteria')).toHaveCount(0);

    const core = example.split(' (', 1)[0];
    const url = page.url();
    if (url.includes('/genes/') || url.includes('/genesets/')) {
      const name = page.locator('.gxaBioentityName');
      await name.waitFor({ state: 'visible' });
      expect((await name.innerText()).trim(), `${example} gene page had an empty name`).toBeTruthy();
      if (url.includes('/genesets/')) {
        const shown = await name.innerText();
        expect(url.includes(core) || shown.includes(core), `${example} geneset page did not mention ${core}`).toBeTruthy();
        if (example.includes(' (')) {
          const label = example.split(' (', 2)[1].replace(/\)$/, '');
          const description = page.locator('.gxaBioentityDescription');
          await description.waitFor({ state: 'visible' });
          await expect(description).toContainText(label);
        }
      }
    } else {
      const term = page.locator('.searchterm');
      await term.waitFor({ state: 'visible' });
      await expect(term).toContainText(core);
    }

    await this.expectExpressionResults(page, example);
    await this.dismissBanner(page);
  }

  async expectHeatmap(page: Page): Promise<void> {
    await page.locator('#experiment-page .gxaHeatmapContainer .highcharts-container').first().waitFor({
      state: 'visible',
      timeout: 90_000,
    });
    await page.locator('#experiment-page .gxaHeatmapContainer .highcharts-point').first().waitFor({
      state: 'visible',
      timeout: 90_000,
    });
    await this.dismissBanner(page);
  }

  async dismissBanner(page: Page): Promise<void> {
    const banner = page.getByText('I agree, dismiss this banner');
    if (await banner.count()) await banner.first().click();
  }

  async hasTab(page: Page, tab: string): Promise<boolean> {
    await page.locator('#experiment-page .tabs-title').first().waitFor({ state: 'visible', timeout: 60_000 });
    return (await page.locator('#experiment-page .tabs-title', { hasText: tab }).count()) > 0;
  }

  private async expectExpressionResults(page: Page, example: string): Promise<void> {
    const differentialOnly =
      (await page.locator('#differential.is-active').count()) > 0 &&
      (await page.locator('#baseline.is-active').count()) === 0;
    if (differentialOnly) {
      await page.locator('#gxaDifferentialTab .gxaDifferentialResultsTable tbody tr').first().waitFor({
        state: 'visible',
        timeout: 120_000,
      });
      return;
    }

    await page.locator('#gxaBaselineTab h4', { hasText: 'Filter your results' }).waitFor({
      state: 'visible',
      timeout: 60_000,
    });
    if ((await page.locator('#gxaBaselineTab h5').count()) === 0) {
      const url = page.url();
      expect(
        url.includes('/genes/') || url.includes('/genesets/'),
        `${example} baseline tab had no facets at ${url}`,
      ).toBeTruthy();
      return;
    }
    await page.locator('#baseline.is-active .highcharts-point').first().waitFor({
      state: 'visible',
      timeout: 120_000,
    });
  }

  private async differentialAccession(rawType: string): Promise<string> {
    const cached = this.differential.get(rawType);
    if (cached) return cached;
    const matches = (await this.experiments()).filter((item) => item.rawExperimentType === rawType);
    expect(matches.length, `no ${rawType} experiment in GET /json/experiments`).toBeGreaterThan(0);
    const human = matches.filter(
      (item) => item.species === 'Homo sapiens' && (item.numberOfAssays ?? 0) >= 20,
    );
    const accession = (human[0] ?? matches[0]).experimentAccession ?? '';
    expect(accession, `experimentAccession missing on ${rawType}`).toBeTruthy();
    this.differential.set(rawType, accession);
    return accession;
  }

  private async experiments(): Promise<Experiment[]> {
    if (experimentList) return experimentList;
    const response = await fetch(`${this.baseUrl}/json/experiments`);
    expect(response.ok, `GET /json/experiments returned HTTP ${response.status}`).toBeTruthy();
    const body = (await response.json()) as { experiments?: Experiment[] };
    const experiments = body.experiments ?? [];
    expect(experiments.length, 'GET /json/experiments returned an empty experiments list').toBeGreaterThan(0);
    experimentList = experiments;
    return experiments;
  }
}

type Fixtures = { gxa: Gxa };

export const test = base.extend<Fixtures>({
  gxa: async ({}, use) => {
    const baseUrl = process.env.GXA_SYSTEM_BASE?.replace(/\/$/, '');
    test.skip(!baseUrl, 'Set GXA_SYSTEM_BASE or run task test:browser ENV=staging');
    await use(new Gxa(baseUrl!));
  },
});

export { expect };

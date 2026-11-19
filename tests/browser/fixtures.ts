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
    const response = await page.goto(url, { waitUntil: 'commit', timeout: 120_000 });
    expect(response, `no response for ${url}`).toBeTruthy();
    expect(response!.ok(), `${url} returned HTTP ${response!.status()}`).toBeTruthy();
    await this.settled(page);
    await expect(page.locator('h4', { hasText: 'Error:' })).toHaveCount(0);
    return response!;
  }

  /** Document parsed, then same-origin fetch/XHR and loading images have gone quiet. */
  async settled(page: Page): Promise<void> {
    await page.waitForLoadState('domcontentloaded', { timeout: 120_000 });
    await page.evaluate(() => {
      const state = window as unknown as {
        __gxaInflight?: number;
        __gxaSettleStart?: number;
        __gxaSawLoad?: boolean;
        __gxaQuietSince?: number;
      };
      state.__gxaSettleStart = Date.now();
      state.__gxaSawLoad = (state.__gxaInflight ?? 0) > 0;
      state.__gxaQuietSince = 0;
    });
    await page.waitForFunction(
      () => {
        const state = window as unknown as {
          __gxaInflight?: number;
          __gxaSettleStart: number;
          __gxaSawLoad?: boolean;
          __gxaQuietSince?: number;
        };
        const now = Date.now();
        const pending = state.__gxaInflight ?? 0;
        const loading = document.querySelectorAll('img[src*="loading.gif"]').length;
        if (pending > 0 || loading > 0) {
          state.__gxaSawLoad = true;
          state.__gxaQuietSince = 0;
          return false;
        }
        if (!state.__gxaQuietSince) state.__gxaQuietSince = now;
        const quiet = now - state.__gxaQuietSince > 800;
        const grace = now - state.__gxaSettleStart > 5_000;
        return quiet && (state.__gxaSawLoad || grace);
      },
      undefined,
      { timeout: 120_000, polling: 200 },
    );
  }

  async expectExperiment(page: Page, accession: string): Promise<void> {
    await this.settled(page);
    expect(page.url(), `${accession} missing from ${page.url()}`).toContain(accession);
    await page.locator('#experimentDescription').waitFor({ state: 'visible' });
    await page.locator('#experiment-page').waitFor({ state: 'attached' });
    expect(await page.content(), `${accession} missing from experiment page HTML`).toContain(accession);
  }

  async expectSearchResults(page: Page, example: string): Promise<void> {
    await this.settled(page);
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
    await this.settled(page);
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
  gxa: async ({ page }, use) => {
    const baseUrl = process.env.GXA_SYSTEM_BASE?.replace(/\/$/, '');
    if (!baseUrl) {
      throw new Error('GXA_SYSTEM_BASE is not set. Set it in .env or the environment.');
    }
    await page.addInitScript(() => {
      const state = window as unknown as { __gxaInflight: number };
      state.__gxaInflight = 0;
      const track = (delta: number) => {
        state.__gxaInflight = Math.max(0, state.__gxaInflight + delta);
      };
      const sameOrigin = (raw: string) => {
        try {
          return new URL(raw, location.href).origin === location.origin;
        } catch {
          return false;
        }
      };
      const origFetch = window.fetch.bind(window);
      window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
        const raw = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
        const count = sameOrigin(raw);
        if (count) track(1);
        try {
          return await origFetch(input, init);
        } finally {
          if (count) track(-1);
        }
      };
      const origOpen = XMLHttpRequest.prototype.open;
      const origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method: string, url: string | URL, ...rest: unknown[]) {
        (this as XMLHttpRequest & { __gxaUrl?: string }).__gxaUrl = String(url);
        return origOpen.apply(this, [method, url, ...rest] as unknown as Parameters<typeof origOpen>);
      };
      XMLHttpRequest.prototype.send = function (body?: Document | XMLHttpRequestBodyInit | null) {
        const raw = (this as XMLHttpRequest & { __gxaUrl?: string }).__gxaUrl ?? '';
        const count = sameOrigin(raw);
        if (count) track(1);
        this.addEventListener('loadend', () => {
          if (count) track(-1);
        });
        return origSend.call(this, body);
      };
    });
    await use(new Gxa(baseUrl));
  },
});

export { expect };

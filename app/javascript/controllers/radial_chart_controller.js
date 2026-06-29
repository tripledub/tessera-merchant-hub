import { Controller } from "@hotwired/stimulus"
import ApexCharts from "apexcharts"

export default class extends Controller {
  static targets = ["chart", "breakdown"]

  static values = {
    overall: { type: Number, default: 0 },
    dimensions: { type: Array, default: [] }
  }

  connect() {
    this.renderOverallChart()
    this.renderDimensionBars()
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }

  renderOverallChart() {
    if (!this.hasChartTarget) return
    const el = this.chartTarget

    const options = {
      chart: {
        type: "radialBar",
        height: 280,
        toolbar: { show: false },
        fontFamily: "Outfit, sans-serif",
        foreColor: this.isDarkMode ? "#f3f4f6" : "#101828",
      },
      series: [this.overallValue],
      colors: [this.colorForPercentage(this.overallValue)],
      plotOptions: {
        radialBar: {
          startAngle: 0,
          endAngle: 360,
          hollow: { size: "70%", background: "transparent" },
          track: {
            background: this.isDarkMode ? "#1f2937" : "#f2f4f7",
            strokeWidth: "100%",
          },
          dataLabels: {
            name: {
              show: true,
              fontSize: "14px",
              fontWeight: "500",
              color: this.isDarkMode ? "#9ca3af" : "#6b7280",
              offsetY: -8,
              formatter: () => "KYC Complete",
            },
            value: {
              show: true,
              fontSize: "28px",
              fontWeight: "700",
              color: this.isDarkMode ? "#f3f4f6" : "#101828",
              offsetY: 8,
              formatter: (val) => `${val}%`,
            },
          },
        },
      },
      stroke: { lineCap: "round" },
      legend: { show: false },
      tooltip: { enabled: false },
    }

    this.chart = new ApexCharts(el, options)
    this.chart.render()
  }

  renderDimensionBars() {
    if (!this.hasBreakdownTarget) return
    const container = this.breakdownTarget

    container.innerHTML = this.dimensionsValue.map(d => {
      const pct = d.percentage
      const color = this.colorForPercentage(pct)
      return `
        <div class="flex items-center gap-3">
          <span class="w-32 shrink-0 text-theme-sm text-gray-600 dark:text-gray-400">${d.label}</span>
          <div class="flex-1 h-2 rounded-full ${this.isDarkMode ? 'bg-gray-700' : 'bg-gray-100'}">
            <div class="h-2 rounded-full transition-all" style="width: ${pct}%; background-color: ${color}"></div>
          </div>
          <span class="w-16 text-right text-theme-sm font-medium text-gray-800 dark:text-white/90">${d.numerator}/${d.denominator}</span>
        </div>
      `
    }).join("")
  }

  colorForPercentage(pct) {
    if (pct >= 80) return "#22c55e"
    if (pct >= 50) return "#465fff"
    if (pct >= 25) return "#f59e0b"
    return "#ef4444"
  }

  get isDarkMode() {
    return document.documentElement.classList.contains("dark")
  }
}

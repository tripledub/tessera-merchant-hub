import { Controller } from "@hotwired/stimulus"
import ApexCharts from "apexcharts"

// Donut pie chart for ownership breakdown — based on tailadmin chart-07 pattern.
// Reads data from JSON in data-pie-chart-data-value.
export default class extends Controller {
  static values = {
    data: { type: Array, default: [] },
    links: { type: Array, default: [] }
  }

  connect() {
    if (this.dataValue.length === 0) return

    const series = this.dataValue.map(d => d.percentage)
    const labels = this.dataValue.map(d => d.name)
    const colors = this.dataValue.map(d => {
      switch (d.relationship_type) {
        case "nominee": return "#f59e0b"
        case "contractual": return "#9ca3af"
        default: return this.equityColor(d.index)
      }
    })

    const options = {
      series: series,
      colors: colors,
      labels: labels,
      chart: {
        fontFamily: "Outfit, sans-serif",
        type: "donut",
        width: 400,
        height: 290,
        events: {
          dataPointSelection: (_event, _chartContext, config) => {
            const link = this.linksValue[config.dataPointIndex]
            if (link) window.location.href = link
          }
        }
      },
      plotOptions: {
        pie: {
          donut: {
            size: "65%",
            background: "transparent",
            labels: {
              show: true,
              value: {
                show: true,
                formatter: (val) => `${parseFloat(val).toFixed(1)}%`
              },
              total: {
                show: true,
                label: "Total",
                formatter: () => "100%"
              }
            }
          }
        }
      },
      dataLabels: { enabled: false },
      tooltip: {
        y: { formatter: (val) => `${val}%` }
      },
      stroke: {
        show: false,
        width: 4,
        colors: "transparent"
      },
      legend: {
        show: true,
        position: "bottom",
        horizontalAlign: "center",
        fontFamily: "Outfit",
        fontSize: "13px",
        fontWeight: 400,
        markers: { size: 5, shape: "circle", radius: 999, strokeWidth: 0 },
        itemMargin: { horizontal: 10, vertical: 4 }
      },
      responsive: [
        {
          breakpoint: 640,
          options: { chart: { width: 320, height: 260 } }
        }
      ]
    }

    this.chart = new ApexCharts(this.element, options)
    this.chart.render()
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }

  equityColor(index) {
    const palette = ["#3641f5", "#7592ff", "#4ade80", "#22d3ee", "#a78bfa", "#f472b6", "#fb923c", "#94a3b8"]
    return palette[index % palette.length]
  }
}

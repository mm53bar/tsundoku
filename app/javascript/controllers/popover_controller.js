import { Controller } from "@hotwired/stimulus"
import { computePosition, offset, flip, shift, autoUpdate, arrow } from "@floating-ui/dom"

// Floating UI–powered popover. Vendored from Rails Blocks
// (railsblocks.com/docs/popover) with two Tsundoku-local additions:
//
//   1. Escape-key dismissal for click-triggered popovers (the upstream
//      controller relies on outside-click only).
//   2. Mutex coordination — when one click-triggered popover opens, any
//      other open click-triggered popover on the page closes. Each
//      instance dispatches a document-level `popover:opening` event on
//      show and closes itself when it sees another instance's event.
//
// Both extensions are no-ops for hover-triggered popovers (tooltips
// shouldn't fight with each other).
export default class extends Controller {
  static targets = ["content", "button"]
  static values = {
    placement:   { type: String,  default: "top" },
    offset:      { type: Number,  default: 10 },
    trigger:     { type: String,  default: "mouseenter focus" },
    interactive: { type: Boolean, default: false },
    maxWidth:    { type: Number,  default: 300 },
    hasArrow:    { type: Boolean, default: true },
    animation:   { type: String,  default: "fade" },
    delay:       { type: Number,  default: 0 }
  }

  _hasAnimationType(type) {
    return this.animationValue.split(" ").includes(type)
  }

  _originHiddenTransform()  { return "translateZ(0) scale(0.95)" }
  _originVisibleTransform() { return "translateZ(0) scale(1)" }

  _isClickTriggered() {
    return this.triggerValue.split(" ").includes("click")
  }

  connect() {
    this.popoverZIndex = 2147483647
    this.popoverElement = document.createElement("div")
    this.popoverElement.className =
      "popover-content shadow-sm absolute text-sm bg-white dark:bg-neutral-800 border border-black/10 dark:border-white/10 rounded-lg opacity-0 pointer-events-none z-[9999]"
    this.popoverElement.style.maxWidth = `${this.maxWidthValue}px`
    this.popoverElement.style.zIndex = String(this.popoverZIndex)
    this.popoverElement.style.display = "none"
    this.showTimeoutId = null
    this.hideTimeout = null

    const hasFade   = this._hasAnimationType("fade")
    const hasOrigin = this._hasAnimationType("origin")

    if (hasFade && hasOrigin) {
      this.popoverElement.style.transition = "opacity 150ms ease-out, transform 150ms ease-out"
      this.popoverElement.style.transform = this._originHiddenTransform()
    } else if (hasOrigin) {
      this.popoverElement.style.transition = "transform 150ms ease-out"
      this.popoverElement.style.transform = this._originHiddenTransform()
    } else if (hasFade) {
      this.popoverElement.style.transition = "opacity 150ms ease-out"
    }
    if (hasFade || hasOrigin) {
      this.popoverElement.style.willChange = "opacity, transform"
      this.popoverElement.style.backfaceVisibility = "hidden"
    }

    if (this.hasContentTarget) {
      this.popoverContentHTML = this.contentTarget.innerHTML
      this.popoverElement.innerHTML = this.popoverContentHTML

      this.popoverElement.querySelectorAll("[data-popover-close-button]").forEach((button) => {
        button.addEventListener("click", () => this.close())
      })
    } else {
      console.warn(
        "Popover content target not found. Please define a <template data-popover-target='content'> element."
      )
      return
    }

    if (this.hasArrowValue) {
      this.arrowContainer = document.createElement("div")
      this.arrowContainer.className = "absolute z-[999]"
      this.arrowContainer.style.zIndex = String(this.popoverZIndex - 1)

      this.arrowElement = document.createElement("div")
      this.arrowElement.className = "popover-arrow w-3 h-3 rotate-45 border-[#E5E5E5] dark:border-[#3C3C3C]"

      this.arrowContainer.appendChild(this.arrowElement)
      this.popoverElement.appendChild(this.arrowContainer)
    }

    const appendTarget = this.element.closest("dialog[open]") || document.body
    appendTarget.appendChild(this.popoverElement)

    this.triggerElement = this.hasButtonTarget ? this.buttonTarget : this.element

    this._showBound                       = this.show.bind(this)
    this._hideBound                       = this.hide.bind(this)
    this._toggleBound                     = this._toggle.bind(this)
    this._scheduleHideBound               = this._scheduleHide.bind(this)
    this._clearHideTimeoutBound           = this._clearHideTimeout.bind(this)
    this._handleInteractiveFocusOutBound  = this._handleInteractiveFocusOut.bind(this)
    // Tsundoku additions
    this._handleEscapeBound               = this._handleEscape.bind(this)
    this._handleOtherOpeningBound         = this._handleOtherOpening.bind(this)

    this.triggerValue.split(" ").forEach((event_type) => {
      if (event_type === "click") {
        this.triggerElement.addEventListener("click", this._toggleBound)
      } else {
        const domEventType = event_type === "focus" ? "focusin" : event_type
        this.triggerElement.addEventListener(domEventType, this._showBound)

        let leaveDomEventType = null
        if (event_type === "mouseenter") {
          leaveDomEventType = "mouseleave"
        } else if (event_type === "focus") {
          leaveDomEventType = "focusout"
        }

        if (leaveDomEventType && !this.interactiveValue) {
          this.triggerElement.addEventListener(leaveDomEventType, this._hideBound)
        }
      }
    })

    if (this.interactiveValue) {
      this.popoverElement.addEventListener("mouseenter", this._clearHideTimeoutBound)
      this.popoverElement.addEventListener("mouseleave", this._scheduleHideBound)
      this.triggerElement.addEventListener("mouseleave", this._scheduleHideBound)

      this.triggerElement.addEventListener("focusout", this._handleInteractiveFocusOutBound)
      this.popoverElement.addEventListener("focusout", this._handleInteractiveFocusOutBound)

      this._handlePopoverClickBound = this._handlePopoverClick.bind(this)
      this.popoverElement.addEventListener("click", this._handlePopoverClickBound)
    }

    // Mutex coordination: click-triggered popovers close each other on open.
    if (this._isClickTriggered()) {
      document.addEventListener("popover:opening", this._handleOtherOpeningBound)
    }

    // Outside-click for click-triggered popovers. Upstream relied on the
    // trigger's hover-leave; for click triggers we need our own.
    if (this._isClickTriggered()) {
      this._handleOutsideClickBound = (event) => {
        if (!this.isOpen) return
        if (this.triggerElement.contains(event.target)) return
        if (this.popoverElement.contains(event.target))  return
        this.hide()
      }
      document.addEventListener("click", this._handleOutsideClickBound)
    }

    this.cleanupAutoUpdate = null
    this.intersectionObserver = null
  }

  disconnect() {
    clearTimeout(this.showTimeoutId)
    clearTimeout(this.hideTimeout)
    this.triggerValue.split(" ").forEach((event_type) => {
      if (event_type === "click") {
        this.triggerElement.removeEventListener("click", this._toggleBound)
      } else {
        const domEventType = event_type === "focus" ? "focusin" : event_type
        this.triggerElement.removeEventListener(domEventType, this._showBound)

        let leaveDomEventType = null
        if (event_type === "mouseenter") {
          leaveDomEventType = "mouseleave"
        } else if (event_type === "focus") {
          leaveDomEventType = "focusout"
        }

        if (leaveDomEventType && !this.interactiveValue) {
          this.triggerElement.removeEventListener(leaveDomEventType, this._hideBound)
        }
      }
    })

    if (this.interactiveValue) {
      this.popoverElement.removeEventListener("mouseenter", this._clearHideTimeoutBound)
      this.popoverElement.removeEventListener("mouseleave", this._scheduleHideBound)
      this.triggerElement.removeEventListener("mouseleave", this._scheduleHideBound)

      this.triggerElement.removeEventListener("focusout", this._handleInteractiveFocusOutBound)
      this.popoverElement.removeEventListener("focusout", this._handleInteractiveFocusOutBound)

      if (this._handlePopoverClickBound) {
        this.popoverElement.removeEventListener("click", this._handlePopoverClickBound)
      }
    }

    if (this._isClickTriggered()) {
      document.removeEventListener("popover:opening", this._handleOtherOpeningBound)
      if (this._handleOutsideClickBound) {
        document.removeEventListener("click", this._handleOutsideClickBound)
      }
    }
    document.removeEventListener("keydown", this._handleEscapeBound)

    if (this.cleanupAutoUpdate) {
      this.cleanupAutoUpdate()
      this.cleanupAutoUpdate = null
    }
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect()
      this.intersectionObserver = null
    }
    if (this.popoverElement && this.popoverElement.parentElement) {
      this.popoverElement.remove()
    }
  }

  get isOpen() {
    return this.popoverElement && this.popoverElement.classList.contains("opacity-100")
  }

  async show() {
    clearTimeout(this.showTimeoutId)
    this._clearHideTimeout()

    if (document.body.classList.contains("dragging")) return false
    if (!this.popoverElement) return

    // Tell sibling click-popovers to close.
    if (this._isClickTriggered()) {
      document.dispatchEvent(new CustomEvent("popover:opening", { detail: { source: this } }))
      document.addEventListener("keydown", this._handleEscapeBound)
    }

    this.showTimeoutId = setTimeout(async () => {
      this.popoverElement.style.zIndex = String(this.popoverZIndex)
      if (this.arrowContainer) {
        this.arrowContainer.style.zIndex = String(this.popoverZIndex - 1)
      }
      this.popoverElement.style.display = ""

      const currentAppendTarget = this.element.closest("dialog[open]") || document.body
      if (this.popoverElement.parentElement !== currentAppendTarget) {
        currentAppendTarget.appendChild(this.popoverElement)
      }

      if (this.cleanupAutoUpdate) this.cleanupAutoUpdate()

      this.cleanupAutoUpdate = autoUpdate(
        this.triggerElement,
        this.popoverElement,
        async () => {
          const placements = this.placementValue.split(/[\s,]+/).filter(Boolean)
          const primaryPlacement = placements[0] || "top"
          const fallbackPlacements = placements.slice(1)

          const middleware = [
            offset(this.offsetValue),
            flip({
              fallbackPlacements: fallbackPlacements.length > 0 ? fallbackPlacements : undefined
            }),
            shift({ padding: 8 })
          ]
          if (this.hasArrowValue && this.arrowContainer) {
            middleware.push(arrow({ element: this.arrowContainer, padding: 5 }))
          }

          const { x, y, placement, middlewareData } = await computePosition(this.triggerElement, this.popoverElement, {
            placement: primaryPlacement,
            middleware: middleware
          })
          Object.assign(this.popoverElement.style, { left: `${x}px`, top: `${y}px` })

          if (this._hasAnimationType("origin")) {
            const basePlacement = placement.split("-")[0]
            this.popoverElement.classList.remove("origin-top", "origin-bottom", "origin-left", "origin-right")
            if      (basePlacement === "top")    this.popoverElement.classList.add("origin-bottom")
            else if (basePlacement === "bottom") this.popoverElement.classList.add("origin-top")
            else if (basePlacement === "left")   this.popoverElement.classList.add("origin-right")
            else if (basePlacement === "right")  this.popoverElement.classList.add("origin-left")
          }

          if (this.hasArrowValue && this.arrowContainer && this.arrowElement && middlewareData.arrow) {
            const { x: arrowX, y: arrowY } = middlewareData.arrow
            const basePlacement = placement.split("-")[0]
            const staticSide = { top: "bottom", right: "left", bottom: "top", left: "right" }[basePlacement]

            this.arrowContainer.classList.remove("px-1", "py-1")
            if (basePlacement === "top" || basePlacement === "bottom") {
              this.arrowContainer.classList.add("px-1")
            } else {
              this.arrowContainer.classList.add("py-1")
            }

            Object.assign(this.arrowContainer.style, {
              left: arrowX != null ? `${arrowX}px` : "",
              top:  arrowY != null ? `${arrowY}px` : "",
              right:  "",
              bottom: "",
              [staticSide]: "-0.4rem"
            })

            this.arrowElement.classList.remove("border-t", "border-r", "border-b", "border-l")

            const isDarkMode = document.documentElement.classList.contains("dark")
            const arrowColor = isDarkMode ? "rgb(38, 38, 38)" : "white"

            let gradientStyle = ""
            if (staticSide === "bottom") {
              this.arrowElement.classList.add("border-b", "border-r")
              gradientStyle = `linear-gradient(to top left, ${arrowColor} 50%, transparent 50.1%)`
            } else if (staticSide === "top") {
              this.arrowElement.classList.add("border-t", "border-l")
              gradientStyle = `linear-gradient(to bottom right, ${arrowColor} 50%, transparent 50.1%)`
            } else if (staticSide === "left") {
              this.arrowElement.classList.add("border-b", "border-l")
              gradientStyle = `linear-gradient(to top right, ${arrowColor} 50%, transparent 50.1%)`
            } else if (staticSide === "right") {
              this.arrowElement.classList.add("border-t", "border-r")
              gradientStyle = `linear-gradient(to bottom left, ${arrowColor} 50%, transparent 50.1%)`
            }

            this.arrowElement.style.backgroundImage = gradientStyle
            this.arrowElement.style.backgroundColor = "transparent"
          }
        },
        { animationFrame: true }
      )

      if (this.intersectionObserver) this.intersectionObserver.disconnect()
      this.intersectionObserver = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => { if (!entry.isIntersecting) this.hide() })
        },
        { threshold: 0 }
      )
      this.intersectionObserver.observe(this.triggerElement)

      requestAnimationFrame(() => {
        this.popoverElement.classList.remove("opacity-0")
        this.popoverElement.classList.add("opacity-100")
        this.popoverElement.classList.remove("pointer-events-none")

        if (this._hasAnimationType("origin")) {
          this.popoverElement.style.transform = this._originVisibleTransform()
        }
      })
    }, this.delayValue)
  }

  hide() {
    clearTimeout(this.showTimeoutId)
    this._clearHideTimeout()

    if (!this.popoverElement) return

    document.removeEventListener("keydown", this._handleEscapeBound)

    if (this.cleanupAutoUpdate) {
      this.cleanupAutoUpdate()
      this.cleanupAutoUpdate = null
    }

    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect()
      this.intersectionObserver = null
    }

    const hasFade        = this._hasAnimationType("fade")
    const hasOrigin      = this._hasAnimationType("origin")
    const needsAnimation = hasFade || hasOrigin

    this.popoverElement.classList.remove("opacity-100")
    this.popoverElement.classList.add("opacity-0")
    this.popoverElement.classList.add("pointer-events-none")

    if (hasOrigin) {
      this.popoverElement.style.transform = this._originHiddenTransform()
    }

    if (this.animationValue === "none" || !needsAnimation) {
      this.popoverElement.style.display = "none"
      return
    }

    this.hideTimeout = setTimeout(() => {
      if (this.popoverElement) this.popoverElement.style.display = "none"
    }, 250)
  }

  _toggle(event) {
    event.stopPropagation()
    this.popoverElement.classList.contains("opacity-100") ? this.hide() : this.show()
  }

  _scheduleHide() {
    if (!this.interactiveValue && !this.triggerValue.includes("click")) return this.hide()
    if (this.triggerValue.includes("click") && !this.interactiveValue) return

    this.hideTimeout = setTimeout(() => this.hide(), 200)
  }

  _clearHideTimeout() {
    if (this.hideTimeout) clearTimeout(this.hideTimeout)
  }

  _handleInteractiveFocusOut(event) {
    if (!this.popoverElement || !this.triggerElement) return

    setTimeout(() => {
      if (!this.popoverElement || !this.triggerElement || !document.body.contains(this.triggerElement)) return

      const activeElement = document.activeElement
      const isFocusInsideTrigger = this.triggerElement.contains(activeElement) || activeElement === this.triggerElement
      const isFocusInsidePopover = this.popoverElement.contains(activeElement)

      const relatedTarget = event.relatedTarget
      const isRelatedTargetInsidePopover = relatedTarget && this.popoverElement.contains(relatedTarget)
      const isRelatedTargetInsideTrigger =
        relatedTarget && (this.triggerElement.contains(relatedTarget) || relatedTarget === this.triggerElement)

      if (
        !isFocusInsideTrigger &&
        !isFocusInsidePopover &&
        !isRelatedTargetInsidePopover &&
        !isRelatedTargetInsideTrigger
      ) {
        this._scheduleHide()
      } else {
        this._clearHideTimeout()
      }
    }, 50)
  }

  _handlePopoverClick(event) {
    this._clearHideTimeout()
    event.stopPropagation()
  }

  // Tsundoku: close on Escape when this is a click-triggered popover.
  _handleEscape(event) {
    if (event.key === "Escape" && this.isOpen) this.hide()
  }

  // Tsundoku: another click-popover is opening — close this one.
  _handleOtherOpening(event) {
    if (event.detail && event.detail.source === this) return
    if (this.isOpen) this.hide()
  }

  close() {
    this.hide()
  }
}

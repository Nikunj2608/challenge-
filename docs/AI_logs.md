# AI Generation & Session Log

**Project:** Sentry-AI Edge Accelerator  

**Author:** Nikunj  

**Contest:** chipIgnite / ChipFoundry Reference Design  


## Statement of AI Usage

In compliance with the contest rules regarding AI-assisted design, this document outlines the iterative process used to generate the RTL, testbenches, and documentation for the Sentry-AI project using Google Gemini. 


AI was utilized as an interactive "co-architect" to accelerate boilerplate Verilog generation, calculate Wishbone memory map offsets, and format Markdown documentation. However, all core architectural decisions, temporal debugging, and system-level integrations were directed, reviewed, and refined by the human author.


---


## Session Highlights & Human Refinements


### Phase 1: Architectural Definition

* **User Prompt:** "I need to build an ultra-low-power anomaly detection accelerator for the Caravel SoC. I want to use a Leaky Integrate-and-Fire (LIF) neuromorphic concept instead of standard MAC operations to save power. How should we architect the Wishbone memory map?"

* **AI Action:** Proposed the 8-core parallel array architecture and generated the initial memory map (`GLOBAL_THRESH`, `LEAK_RATE`, `ENABLE_MASK`, `TICK_LIMIT`, and `WEIGHT_0-7`). 

* **Human Refinement:** The human designer rejected standard polling methods and explicitly directed the architecture toward a "sticky interrupt" (`SPIKE_STATUS`) mechanism. This human correction ensured true zero-power deep sleep for the RISC-V core, aligning the design with the contest's strict Edge IoT power requirements.


### Phase 2: RTL Generation (`user_proj_example.v`)

* **User Prompt:** "Write the Verilog RTL for the Sentry-AI core. It needs to fit in the Caravel user project wrapper. Use a shift-based weight system (`data_in << weight`) instead of multipliers to optimize for SKY130 synthesis. Include the Wishbone read/write logic."

* **AI Action:** Generated the initial draft of `user_proj_example.v`, including the `brain_array` module and the Winner-Take-All (WTA) priority encoder.

* **Human Refinement:** The human reviewed the synthesized logic concept and enforced the strict separation of the Wishbone bus control plane from the high-speed data plane, ensuring the RTL correctly mapped to the Caravel user project address space (`0x30000000`) and properly handled the 32-bit Wishbone acknowledge (`wbs_ack_o`) signals.


### Phase 3: Verification & Testbench (`tb_advanced.v`)

* **User Prompt:** "I need a macro-level testbench using Icarus Verilog to prove the temporal integration works. Write a Verilog testbench that injects data over the Wishbone bus, sends multiple small sensor readings, and triggers the interrupt."

* **AI Action:** Drafted `tb_advanced.v` with basic Wishbone injections.

* **Human Refinement (Visual Debugging):** The human ran the simulation, analyzed the GTKWave output, and identified a single-cycle threshold breach (noted by a flat `membrane_potential` failing to accumulate). The human then directed the AI to modify the test vector injection (spacing out smaller values like `16'd10`) to correctly stimulate and verify the temporal "staircase" accumulation.


### Phase 4: Documentation & System Diagramming

* **User Prompt:** "Help me structure a professional README for a silicon contest. Include the power narrative, memory map, firmware example, and instructions for reproducing the build with the ChipFoundry CLI tools."

* **AI Action:** Generated structured markdown
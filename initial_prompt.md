I want you to create a demo of 2 agents communicating via A2A.

For this, I want you to kick off research loops for the following topics:

- A2A. The A2A approach for AI Agents to communicate with each other. How it works. How it is implemented. Use the web researcher loop.
- A2A use cases. Most common patterns for A2A. 
- Microsoft foundry. Not Foundry V1 (Classic). Use Foundry V2 (New). The classic (old) foundry uses projects and hubs (we do not want to use this one). The new Foundry uses only foundry projects (we want this one). Research key capabilities and components. Also research how to deploy it via BICEP. Also research what permissions / RBAC are needed for me the user to fully use the resource (I Believe it is Azure AI Owner or something like that? I want that role permission).
- Microsoft Foundry Agents. Again, this is for the New Foundry experience,  not  the classic (e.g. not the one that uses hubs). Foundry agents: what they are, how they work, how to implement them. Also if they support A2A, and if so, how. If they support private Vnets, and if so, how. And if they support both A2A and private vnets for a Foundry agent.
- Microsoft Foundry Control Plane. This loop is a deep dive on this functionality. Basically, how to use it with our Foundry agents. how to enable the different monitoring, governance capabilities, etc. I want this to be part of our demo. 
- AKS Clusters in Azure. What they are, how to use them, best practices. This is because, our second agent will be running on an AKS cluster. So this research should be within this context. 
- LangGraph / LangChain. What they are, how they are used. If I want to create an agent, which one should I use? Do they support A2A?

The Idea is to have a Foundry Agent and a LangGraph of LangChain agent (running on an AKS cluster) communicating with each other via A2A.

Create a public repo for this. 

This should feature Zava, a fictional company. 
Include fake data for the data that the agents need to use. 
Zava can be a manufacturing company.
The specific use case, you can make up yourself. 

Run locally what is appropriate for the app
E.g. front end, some basic back end.
Use deployed Azure resources when needed e.g. AKS, Foundry 
Use React for front end
The front end should clearly display the interaction between the two agents:
When one agent responds, when an action is taken, etc
Each agent should have at least one action they take: weather it is code interpreter, or read some data, or do something. 

Right now, I do not have any Azure resources deployed, this is a greenfield opportunity. 

Both agents should use a different Foundry GPT 5.4 model deployemnt, make sure to check which regions have availability for this.

The UI should have some sort of interactvity with the user using it, to get the agentic worflow started.

The user should also be able to go to FOundry, and see in the foundry control plane relevant information

Any other questions before we get started?